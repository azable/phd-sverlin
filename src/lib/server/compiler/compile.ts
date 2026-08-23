/**
 * Server boundary for invoking the Haskell compiler and decoding its visualization.
 *
 * @packageDocumentation
 */

import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
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
  signal?: AbortSignal;
};

type CompileRun = CompileDebug & {
  timedOut: boolean;
};

type RunCompileOptions = {
  signal?: AbortSignal;
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
export async function compileSource({
  sourceContent,
  sourceLabel,
  seed,
  owner,
  signal
}: CompileSourceOptions): Promise<CompileVisualizationResult> {
  const cwd = process.cwd();
  let outputPath: string;
  let sourcePath: string;

  try {
    const output = await createCompileOutput({ owner, seed });
    outputPath = output.outputPath;
    sourcePath = path.join(output.outputDir, 'source', 'Main.sverlin');
    await mkdir(path.dirname(sourcePath), { recursive: true });
    await writeFile(sourcePath, sourceContent, 'utf8');
  } catch (error) {
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

  const { command, args } = compileCommand(seed, outputPath, sourcePath, sourceLabel);

  const timeoutMs = readCompileTimeoutMs();
  let debug = await runCompile(command, args, cwd, timeoutMs, {
    signal
  });
  let compiledJson = '';

  try {
    compiledJson = await readFile(outputPath, 'utf8');
  } catch {
    compiledJson = '';
  }

  debug = { ...debug, outputPath };
  if (debug.error) {
    const diagnostics = diagnosticsForFailure(debug, debug.error);
    return {
      ok: false,
      error: debug.error,
      debug,
      status: 500,
      diagnostics,
      failureKind: classifyCompileFailure(debug)
    };
  }

  if (debug.timedOut) {
    const error = `Compile backend timed out after ${formatDuration(timeoutMs)}.`;
    return {
      ok: false,
      error,
      debug,
      status: 504,
      diagnostics: diagnosticsForFailure(debug, error),
      failureKind: 'timeout'
    };
  }

  if (debug.exitCode !== 0) {
    const error = `Compile backend exited with code ${debug.exitCode}.`;
    return {
      ok: false,
      error,
      debug,
      status: 500,
      diagnostics: diagnosticsForFailure(debug, error),
      failureKind: classifyCompileFailure(debug)
    };
  }

  try {
    const visualization = decodeVisualization(compiledJson);
    const bundle = await readCompileBundle(outputPath, compiledJson, visualization);
    return {
      ok: true,
      visualization,
      resources: bundle.resources,
      provenance: bundle.provenance,
      targetDiagnostics: bundle.targetDiagnostics,
      debug
    };
  } catch (err) {
    const error = `Compile backend wrote an invalid output package: ${
      err instanceof Error ? err.message : String(err)
    }`;
    return {
      ok: false,
      error,
      debug,
      status: 502,
      diagnostics: diagnosticsForFailure(debug, error),
      failureKind: 'invalid-output'
    };
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
  const rawManifest = JSON.parse(await readFile(manifestPath, 'utf8')) as unknown;
  const parsed = v.safeParse(compileManifestSchema, rawManifest);
  if (!parsed.success) throw new Error(`Invalid compile manifest: ${v.summarize(parsed.issues)}`);

  const manifest = parsed.output;
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
      const bytes = await readFile(attachmentPath);
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
      stdio: ['ignore', 'pipe', 'pipe']
    });
    let stdout = '';
    let stderr = '';
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
      stdout += chunk;
      options.onStdout?.(chunk, stdout);
    });

    child.stderr.on('data', (chunk: string) => {
      stderr += chunk;
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

/** Build the Node wrapper command used to invoke the Haskell compiler. */
export function compileCommand(
  seed: number,
  outputPath: string,
  sourcePath: string,
  sourceLabel: string
): CompileCommand {
  const args = [
    'scripts/run-compile.mjs',
    '--',
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

  return { command: 'node', args };
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
