/**
 * Server boundary for invoking the Haskell compiler and decoding its visualization.
 *
 * @packageDocumentation
 */

import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdir, readFile, rm, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import * as v from 'valibot';

import { decodeVisualization, type Visualization } from '$lib/shared/visualization';
import type {
  CompilationProvenance,
  CompilationResource,
  CompilerDiagnostic,
  TargetDiagnostic
} from '$lib/shared/projects/events/values';

import { classifyCompileFailure, parseCompilerDiagnostics } from './diagnostics';
import {
  compilerWorkspaceLockPath,
  CompilerNotReadyError,
  compilerSourceFingerprint,
  preparedCompilerEnvironment,
  readPreparedCompiler
} from './prepared-compiler.js';
import { compilerScheduler, type CompilePriority } from './scheduler';
import { createCompileOutput } from './workspace-output.js';

/** Process and diagnostic metadata captured for one compiler invocation. */
export type CompileDebug = {
  command: string;
  args: string[];
  cwd: string;
  outputPath?: string;
  timeoutMs?: number;
  timedOut?: boolean;
  durationMs: number;
  exitCode: number | null;
  stdout: string;
  stderr: string;
  prefetched?: boolean;
  error?: string;
};

/** Stable categories used to route and present compilation failures. */
export type CompileFailureKind =
  | 'source'
  | 'pipeline'
  | 'infrastructure'
  | 'timeout'
  | 'invalid-output'
  | 'cancelled';

/** Success or structured failure returned by a visualization compilation. */
export type CompileVisualizationResult =
  | {
      ok: true;
      visualization: Visualization;
      resources: CompileResource[];
      provenance: CompileProvenance;
      targetDiagnostics: TargetDiagnostic[];
      compilerSourceSha256?: string;
      debug: CompileDebug;
    }
  | {
      ok: false;
      error: string;
      debug: CompileDebug;
      status: number;
      diagnostics: CompilerDiagnostic[];
      failureKind?: CompileFailureKind;
    };

/** Verified resource bytes emitted beside a compiler result. */
export type CompileResource = CompilationResource & { bytes: Uint8Array };

/** Deterministic toolchain provenance emitted by the compiler package. */
export type CompileProvenance = CompilationProvenance;

/** Inputs required to compile an isolated source snapshot. */
export type CompileSourceOptions = {
  sourceContent: string;
  sourceLabel: string;
  seed: number;
  owner: string;
  priority?: CompilePriority;
  signal?: AbortSignal;
};

type CompileRun = CompileDebug & {
  timedOut: boolean;
};

type RunCompileOptions = {
  signal?: AbortSignal;
  env?: NodeJS.ProcessEnv;
  onStdout?: (chunk: string, stdout: string) => void;
  onStderr?: (chunk: string, stderr: string) => void;
};

/** Executable command and arguments used to invoke the compiler wrapper. */
export type CompileCommand = {
  command: string;
  args: string[];
};

const defaultCompileTimeoutMs = 300_000;
const timeoutKillGraceMs = 1_000;
const compileTimeoutEnvVar = 'SVERLIN_COMPILE_TIMEOUT_MS';
const maxCompileSourceBytes = 512 * 1024;
const maxCompilerLogBytes = 2 * 1024 * 1024;
const maxVisualizationBytes = 32 * 1024 * 1024;
const maxManifestBytes = 1024 * 1024;
const maxResourceBytes = 16 * 1024 * 1024;
const maxResourceBundleBytes = 64 * 1024 * 1024;
const maxResourceCount = 128;
const compilerLockConflictExitCode = 75;
const sha256Schema = v.pipe(v.string(), v.regex(/^[a-f0-9]{64}$/));
const manifestArtifactSchema = v.strictObject({
  relativePath: v.string(),
  mediaType: v.pipe(v.string(), v.nonEmpty()),
  sha256: sha256Schema,
  byteLength: v.pipe(v.number(), v.safeInteger(), v.minValue(0))
});
const compileManifestSchema = v.strictObject({
  manifestVersion: v.literal(1),
  primary: manifestArtifactSchema,
  attachments: v.array(manifestArtifactSchema),
  diagnostics: v.array(
    v.strictObject({
      severity: v.picklist(['info', 'warning']),
      code: v.pipe(v.string(), v.nonEmpty()),
      message: v.string()
    })
  ),
  provenance: v.strictObject({
    packageVersion: v.literal(1),
    textRunFormatVersion: v.literal(2),
    shapingEngine: v.string(),
    shapingEngineVersion: v.string(),
    fontCatalogSha256: v.nullable(sha256Schema)
  })
});

/** Compile Sverlin source in an isolated workspace and decode its output. */
export async function compileSource(
  options: CompileSourceOptions
): Promise<CompileVisualizationResult> {
  const { sourceContent, sourceLabel, seed, owner, priority = 'foreground', signal } = options;
  const cwd = process.cwd();
  if (Buffer.byteLength(sourceContent, 'utf8') > maxCompileSourceBytes) {
    const error = `Compile source exceeds the ${maxCompileSourceBytes} byte limit.`;
    const debug = emptyCompileDebug(cwd, error);
    return {
      ok: false,
      error,
      debug,
      status: 413,
      diagnostics: diagnosticsForFailure(debug, error),
      failureKind: 'source'
    };
  }
  let outputPath: string;
  let outputDir: string | undefined;
  let sourcePath: string;

  try {
    const output = await createCompileOutput({ owner, seed });
    outputDir = output.outputDir;
    outputPath = output.outputPath;
    sourcePath = path.join(output.outputDir, 'source', 'Main.sverlin');
    await mkdir(path.dirname(sourcePath), { recursive: true });
    await writeFile(sourcePath, sourceContent, 'utf8');
  } catch (error) {
    if (outputDir) {
      await rm(outputDir, { recursive: true, force: true }).catch(() => undefined);
    }
    const message = error instanceof Error ? error.message : String(error);
    const debug = emptyCompileDebug(cwd, message);
    return {
      ok: false,
      error: message,
      debug,
      status: 500,
      diagnostics: diagnosticsForFailure(debug, message),
      failureKind: 'infrastructure'
    };
  }

  const finish = async (result: CompileVisualizationResult) => {
    await rm(outputDir!, { recursive: true, force: true }).catch(() => undefined);
    return result;
  };

  let prepared;
  try {
    prepared = await readPreparedCompiler();
  } catch (error) {
    const message =
      error instanceof CompilerNotReadyError
        ? `${error.message} Run \`pnpm run prepare:compiler\`.`
        : error instanceof Error
          ? error.message
          : String(error);
    const debug = emptyCompileDebug(cwd, message);
    return finish({
      ok: false,
      error: message,
      debug,
      status: 503,
      diagnostics: diagnosticsForFailure(debug, message),
      failureKind: 'infrastructure'
    });
  }

  const direct = compileCommand(prepared.binaryPath, seed, outputPath, sourcePath, sourceLabel);
  const { command, args } = compilerLockCommand(
    direct.command,
    direct.args,
    compilerWorkspaceLockPath()
  );

  const timeoutMs = readCompileTimeoutMs();
  let debug: CompileRun;
  try {
    debug = await compilerScheduler.run(
      priority,
      (scheduledSignal) =>
        runCompile(command, args, cwd, timeoutMs, {
          signal: scheduledSignal,
          env: preparedCompilerEnvironment(prepared)
        }),
      signal
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const failed = emptyCompileDebug(cwd, message);
    return finish({
      ok: false,
      error: message,
      debug: failed,
      status: errorName(error) === 'CompileQueueFullError' ? 429 : 503,
      diagnostics: diagnosticsForFailure(failed, message),
      failureKind:
        errorName(error) === 'CompilerShuttingDownError' || errorName(error) === 'AbortError'
          ? 'cancelled'
          : 'infrastructure'
    });
  }
  let compiledJson = '';

  let outputReadError: string | undefined;
  try {
    compiledJson = await readTextFileBounded(
      outputPath,
      maxVisualizationBytes,
      'Compiler visualization output'
    );
  } catch (error) {
    outputReadError = error instanceof Error ? error.message : String(error);
  }

  debug = { ...debug, outputPath };
  if (debug.error) {
    const diagnostics = diagnosticsForFailure(debug, debug.error);
    return finish({
      ok: false,
      error: debug.error,
      debug,
      status: 500,
      diagnostics,
      failureKind: classifyCompileFailure(debug)
    });
  }

  if (debug.timedOut) {
    const error = `Compile backend timed out after ${formatDuration(timeoutMs)}.`;
    return finish({
      ok: false,
      error,
      debug,
      status: 504,
      diagnostics: diagnosticsForFailure(debug, error),
      failureKind: 'timeout'
    });
  }

  if (debug.exitCode !== 0) {
    const lockBusy = debug.exitCode === compilerLockConflictExitCode;
    const error = lockBusy
      ? 'Compiler preparation is in progress. Try again when the prepared compiler is ready.'
      : `Compile backend exited with code ${debug.exitCode}.`;
    return finish({
      ok: false,
      error,
      debug,
      status: lockBusy ? 503 : 500,
      diagnostics: diagnosticsForFailure(debug, error),
      failureKind: lockBusy ? 'infrastructure' : classifyCompileFailure(debug)
    });
  }

  try {
    if ((await compilerSourceFingerprint()) !== prepared.sourceSha256) {
      const error =
        'Compiler inputs changed while this request was queued or running. Prepare the compiler and try again.';
      return finish({
        ok: false,
        error,
        debug,
        status: 503,
        diagnostics: diagnosticsForFailure(debug, error),
        failureKind: 'infrastructure'
      });
    }
  } catch (cause) {
    const error = `Compiler inputs could not be verified after compilation: ${
      cause instanceof Error ? cause.message : String(cause)
    }`;
    return finish({
      ok: false,
      error,
      debug,
      status: 503,
      diagnostics: diagnosticsForFailure(debug, error),
      failureKind: 'infrastructure'
    });
  }

  if (outputReadError) {
    const error = `Compile backend did not produce a readable output package: ${outputReadError}`;
    return finish({
      ok: false,
      error,
      debug,
      status: 502,
      diagnostics: diagnosticsForFailure(debug, error),
      failureKind: 'invalid-output'
    });
  }

  try {
    const visualization = decodeVisualization(compiledJson);
    const bundle = await readCompileBundle(outputPath, compiledJson, visualization);
    return finish({
      ok: true,
      visualization,
      resources: bundle.resources,
      provenance: bundle.provenance,
      targetDiagnostics: bundle.targetDiagnostics,
      compilerSourceSha256: prepared.sourceSha256,
      debug
    });
  } catch (err) {
    const error = `Compile backend wrote an invalid output package: ${
      err instanceof Error ? err.message : String(err)
    }`;
    return finish({
      ok: false,
      error,
      debug,
      status: 502,
      diagnostics: diagnosticsForFailure(debug, error),
      failureKind: 'invalid-output'
    });
  }
}

/** Read, constrain, and cryptographically verify one compiler output package. */
export async function readCompileBundle(
  outputPath: string,
  compiledJson: string,
  visualization: Visualization
): Promise<{
  resources: CompileResource[];
  provenance: CompileProvenance;
  targetDiagnostics: TargetDiagnostic[];
}> {
  const manifestPath = `${outputPath}.manifest.json`;
  const rawManifest = JSON.parse(
    await readTextFileBounded(manifestPath, maxManifestBytes, 'Compile manifest')
  ) as unknown;
  const parsed = v.safeParse(compileManifestSchema, rawManifest);
  if (!parsed.success) throw new Error(`Invalid compile manifest: ${v.summarize(parsed.issues)}`);

  const manifest = parsed.output;
  if (manifest.attachments.length > maxResourceCount) {
    throw new Error(`Compile manifest exceeds the ${maxResourceCount} attachment limit.`);
  }
  const totalResourceBytes = manifest.attachments.reduce(
    (total, attachment) => total + attachment.byteLength,
    0
  );
  if (manifest.attachments.some(({ byteLength }) => byteLength > maxResourceBytes)) {
    throw new Error(`Compile attachment exceeds the ${maxResourceBytes} byte limit.`);
  }
  if (totalResourceBytes > maxResourceBundleBytes) {
    throw new Error(`Compile attachments exceed the ${maxResourceBundleBytes} byte bundle limit.`);
  }
  if (manifest.primary.relativePath !== path.basename(outputPath)) {
    throw new Error('Compile manifest primary path does not match the requested output.');
  }
  if (manifest.primary.mediaType !== 'application/json') {
    throw new Error('Compile manifest primary media type must be application/json.');
  }
  verifyBytes(Buffer.from(compiledJson), manifest.primary, 'primary visualization');

  const descriptors = new Map(
    visualization.resources.map((descriptor) => [descriptor.descriptorId, descriptor])
  );
  if (descriptors.size !== visualization.resources.length) {
    throw new Error('Visualization contains duplicate resource descriptors.');
  }
  if (manifest.attachments.length !== descriptors.size) {
    throw new Error('Compile manifest attachments do not match visualization resources.');
  }
  const attachmentIds = manifest.attachments.map(({ sha256 }) => `sha256-${sha256}`);
  if (new Set(attachmentIds).size !== attachmentIds.length) {
    throw new Error('Compile manifest contains duplicate attachments.');
  }

  const resources = await Promise.all(
    manifest.attachments.map(async (attachment): Promise<CompileResource> => {
      const id = `sha256-${attachment.sha256}`;
      if (attachment.relativePath !== `resources/${id}`) {
        throw new Error(
          `Unsafe or non-canonical compile attachment path ${attachment.relativePath}.`
        );
      }
      const descriptor = descriptors.get(id);
      if (
        !descriptor ||
        descriptor.descriptorSha256 !== attachment.sha256 ||
        descriptor.descriptorMediaType !== attachment.mediaType ||
        descriptor.descriptorByteLength !== attachment.byteLength
      ) {
        throw new Error(`Compile attachment ${id} does not match its IR descriptor.`);
      }

      const attachmentPath = path.join(
        path.dirname(outputPath),
        ...attachment.relativePath.split('/')
      );
      const bytes = await readBinaryFileBounded(
        attachmentPath,
        maxResourceBytes,
        `Compile attachment ${id}`
      );
      verifyBytes(bytes, attachment, id);
      return {
        id,
        kind: descriptor.descriptorKind,
        sha256: attachment.sha256,
        mediaType: attachment.mediaType,
        byteLength: attachment.byteLength,
        bytes
      };
    })
  );

  return {
    resources,
    targetDiagnostics: manifest.diagnostics,
    provenance: {
      packageVersion: manifest.provenance.packageVersion,
      textRunFormatVersion: manifest.provenance.textRunFormatVersion,
      shapingEngine: manifest.provenance.shapingEngine,
      shapingEngineVersion: manifest.provenance.shapingEngineVersion,
      ...(manifest.provenance.fontCatalogSha256
        ? { fontCatalogSha256: manifest.provenance.fontCatalogSha256 }
        : {})
    }
  };
}

function verifyBytes(
  bytes: Uint8Array,
  expected: { byteLength: number; sha256: string },
  label: string
): void {
  if (bytes.byteLength !== expected.byteLength) {
    throw new Error(`Compile ${label} has an unexpected byte length.`);
  }
  const digest = createHash('sha256').update(bytes).digest('hex');
  if (digest !== expected.sha256) throw new Error(`Compile ${label} failed SHA-256 verification.`);
}

function diagnosticsForFailure(debug: CompileDebug, fallback: string) {
  const parsed = parseCompilerDiagnostics(debug.stderr);
  return parsed.length > 0
    ? parsed
    : [{ severity: 'unknown' as const, message: fallback, raw: fallback }];
}

/** Run a compiler process with streaming diagnostics, cancellation, and a hard timeout. */
export function runCompile(
  command: string,
  args: string[],
  cwd: string,
  timeoutMs = readCompileTimeoutMs(),
  options: RunCompileOptions = {}
): Promise<CompileRun> {
  return new Promise((resolve) => {
    const startedAt = Date.now();
    const child = spawn(command, args, {
      cwd,
      detached: process.platform !== 'win32',
      env: options.env,
      stdio: ['ignore', 'pipe', 'pipe']
    });
    let stdout = '';
    let stderr = '';
    let stdoutTruncated = false;
    let stderrTruncated = false;
    let settled = false;
    let timedOut = false;
    let cancelled = false;
    let killTimer: ReturnType<typeof setTimeout> | undefined;
    let settleTimer: ReturnType<typeof setTimeout> | undefined;

    function terminate(signal: NodeJS.Signals) {
      terminateCompile(child.pid, signal);
    }

    function forceSettle(error?: string) {
      settle({
        command,
        args,
        cwd,
        timeoutMs,
        durationMs: Date.now() - startedAt,
        exitCode: null,
        stdout,
        stderr,
        error,
        timedOut
      });
    }

    const timer = setTimeout(() => {
      timedOut = true;
      terminate('SIGTERM');

      killTimer = setTimeout(() => {
        terminate('SIGKILL');
      }, timeoutKillGraceMs);

      settleTimer = setTimeout(() => {
        forceSettle();
      }, timeoutKillGraceMs * 2);
    }, timeoutMs);

    const abortCompile = () => {
      cancelled = true;
      terminate('SIGTERM');

      killTimer = setTimeout(() => {
        terminate('SIGKILL');
      }, timeoutKillGraceMs);

      settleTimer = setTimeout(() => {
        forceSettle('Compile backend was cancelled.');
      }, timeoutKillGraceMs * 2);
    };

    if (options.signal?.aborted) {
      abortCompile();
    } else {
      options.signal?.addEventListener('abort', abortCompile, { once: true });
    }

    function clearTimers() {
      clearTimeout(timer);
      if (killTimer) clearTimeout(killTimer);
      if (settleTimer) clearTimeout(settleTimer);
      options.signal?.removeEventListener('abort', abortCompile);
    }

    function settle(result: CompileRun) {
      if (settled) return;

      settled = true;
      clearTimers();
      resolve(result);
    }

    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');

    child.stdout.on('data', (chunk: string) => {
      const captured = appendBoundedLog(stdout, chunk);
      stdout = captured.value;
      stdoutTruncated ||= captured.truncated;
      options.onStdout?.(chunk, stdout);
    });

    child.stderr.on('data', (chunk: string) => {
      const captured = appendBoundedLog(stderr, chunk);
      stderr = captured.value;
      stderrTruncated ||= captured.truncated;
      options.onStderr?.(chunk, stderr);
    });

    child.on('error', (err) => {
      settle({
        command,
        args,
        cwd,
        timeoutMs,
        durationMs: Date.now() - startedAt,
        exitCode: null,
        stdout,
        stderr,
        error: err.message,
        timedOut
      });
    });

    child.on('close', (exitCode) => {
      const error = cancelled ? 'Compile backend was cancelled.' : undefined;

      if (stdoutTruncated) stdout += '\n[compiler stdout truncated]\n';
      if (stderrTruncated) stderr += '\n[compiler stderr truncated]\n';

      settle({
        command,
        args,
        cwd,
        timeoutMs,
        durationMs: Date.now() - startedAt,
        exitCode,
        stdout,
        stderr,
        error,
        timedOut
      });
    });
  });
}

async function readTextFileBounded(destination: string, maximum: number, label: string) {
  const bytes = await readBinaryFileBounded(destination, maximum, label);
  return Buffer.from(bytes).toString('utf8');
}

async function readBinaryFileBounded(destination: string, maximum: number, label: string) {
  const details = await stat(destination);
  if (!details.isFile()) throw new Error(`${label} is not a regular file.`);
  if (details.size > maximum) throw new Error(`${label} exceeds the ${maximum} byte limit.`);
  const bytes = await readFile(destination);
  if (bytes.byteLength > maximum) throw new Error(`${label} exceeds the ${maximum} byte limit.`);
  return bytes;
}

function appendBoundedLog(current: string, chunk: string) {
  const currentBytes = Buffer.byteLength(current, 'utf8');
  const remaining = maxCompilerLogBytes - currentBytes;
  if (remaining <= 0) return { value: current, truncated: true };
  const incoming = Buffer.from(chunk);
  if (incoming.byteLength <= remaining) {
    return { value: current + chunk, truncated: false };
  }
  return {
    value: current + incoming.subarray(0, remaining).toString('utf8'),
    truncated: true
  };
}

/** Build the direct command used to invoke one prepared Haskell compiler. */
export function compileCommand(
  binaryPath: string,
  seed: number,
  outputPath: string,
  sourcePath: string,
  sourceLabel: string
): CompileCommand {
  const args = [
    '--source',
    sourcePath,
    '--source-label',
    sourceLabel,
    '--output',
    outputPath,
    '--target',
    'ir-json',
    '--details',
    '--seed',
    String(seed)
  ];

  return { command: binaryPath, args };
}

/** Wrap a compiler child in a non-blocking shared lock against Cabal preparation. */
export function compilerLockCommand(
  command: string,
  args: string[],
  lockPath: string
): CompileCommand {
  if (process.platform === 'win32') return { command, args };
  return {
    command: 'flock',
    args: [
      '--shared',
      '--nonblock',
      '--no-fork',
      '--conflict-exit-code',
      String(compilerLockConflictExitCode),
      lockPath,
      command,
      ...args
    ]
  };
}

function emptyCompileDebug(cwd: string, error: string): CompileDebug {
  return {
    command: 'node',
    args: [],
    cwd,
    durationMs: 0,
    exitCode: null,
    stdout: '',
    stderr: error
  };
}

function errorName(error: unknown) {
  return error instanceof Error ? error.name : undefined;
}

function terminateCompile(pid: number | undefined, signal: NodeJS.Signals) {
  if (pid === undefined) return;

  try {
    process.kill(process.platform === 'win32' ? pid : -pid, signal);
  } catch {
    try {
      process.kill(pid, signal);
    } catch {
      // The process may already have exited between the timeout and signal.
    }
  }
}

function readCompileTimeoutMs() {
  const rawValue = process.env[compileTimeoutEnvVar];
  if (!rawValue) return defaultCompileTimeoutMs;

  const parsedValue = Number(rawValue);
  if (!Number.isInteger(parsedValue) || parsedValue <= 0) {
    return defaultCompileTimeoutMs;
  }

  return parsedValue;
}

function formatDuration(timeoutMs: number) {
  return timeoutMs % 1_000 === 0 ? `${timeoutMs / 1_000}s` : `${timeoutMs}ms`;
}
