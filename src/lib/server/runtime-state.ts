/** Process lifecycle, readiness, and crash recovery for the packaged Svelte server. */

import { randomUUID } from 'node:crypto';
import { mkdir, open, readdir, rename, rm } from 'node:fs/promises';
import path from 'node:path';

import { validateAuthenticationConfiguration } from '$lib/server/auth';
import { visualizationService } from '$lib/server/compiler';
import { closeDatabase, sqlClient } from '$lib/server/db';
import { projectOperationExecutor } from '$lib/server/projects/operations';
import { projectRepository } from '$lib/server/projects/repository';

import { runtimeScratchDir } from './runtime-config';

type PreparedCompilerSummary = {
  sourceSha256: string;
  preparedAt: string;
};

type RuntimeLifecycle = {
  initialized: boolean;
  draining: boolean;
  error?: string;
  warnings: string[];
  recoveredOperations: number;
  compiler?: PreparedCompilerSummary;
  compilerCheckedAt: number;
};

type SharedRuntimeState = {
  lifecycle: RuntimeLifecycle;
  initialization?: Promise<void>;
};

/** Non-sensitive process readiness state used by health and version routes. */
export type RuntimeReadiness = {
  ready: boolean;
  initialized: boolean;
  draining: boolean;
  error?: string;
  warnings: string[];
  recoveredOperations: number;
  compiler: PreparedCompilerSummary | undefined;
  compilerQueue: ReturnType<typeof visualizationService.status>;
  operations: ReturnType<typeof projectOperationExecutor.status>;
};

const runtimeStateKey = Symbol.for('sverlin.runtime-state');
const runtimeGlobal = globalThis as typeof globalThis & {
  [runtimeStateKey]?: SharedRuntimeState;
};
const sharedRuntime = (runtimeGlobal[runtimeStateKey] ??= {
  lifecycle: {
    initialized: false,
    draining: false,
    warnings: [],
    recoveredOperations: 0,
    compilerCheckedAt: 0
  }
});
const lifecycle = sharedRuntime.lifecycle;

/** Validate writable state and the prepared compiler before accepting requests. */
export function initializeRuntime(): Promise<void> {
  if (!sharedRuntime.initialization) {
    const attempt = initializeRuntimeOnce();
    sharedRuntime.initialization = attempt;
    void attempt.then(undefined, () => {
      if (sharedRuntime.initialization === attempt) sharedRuntime.initialization = undefined;
    });
  }
  return sharedRuntime.initialization;
}

/** Stop admission, cancel active work, and close process-owned resources. */
export async function shutdownRuntime(): Promise<void> {
  lifecycle.draining = true;
  await projectOperationExecutor.shutdown(shutdownTimeoutMs());
  visualizationService.shutdown();
  await closeDatabase();
}

/** Return a fresh, non-sensitive readiness snapshot. */
export async function runtimeReadiness(forceCompilerCheck = false): Promise<RuntimeReadiness> {
  if (!sharedRuntime.initialization) {
    try {
      await initializeRuntime();
    } catch {
      // Initialization records the non-sensitive error exposed below. A later
      // readiness request retries after transient dependency failures.
    }
  }
  if (
    lifecycle.initialized &&
    (forceCompilerCheck || Date.now() - lifecycle.compilerCheckedAt >= compilerCheckIntervalMs())
  ) {
    await checkPreparedCompiler();
  }
  const databaseError = await databaseReadinessError();
  const activeError = lifecycle.error ?? databaseError;
  const ready = lifecycle.initialized && !lifecycle.draining && !activeError;
  return {
    ready,
    initialized: lifecycle.initialized,
    draining: lifecycle.draining,
    ...(activeError ? { error: activeError } : {}),
    warnings: [...lifecycle.warnings],
    recoveredOperations: lifecycle.recoveredOperations,
    compiler: lifecycle.compiler,
    compilerQueue: visualizationService.status(),
    operations: projectOperationExecutor.status()
  };
}

async function initializeRuntimeOnce() {
  try {
    validateAuthenticationConfiguration();
    await Promise.all([assertWritableDirectory(runtimeScratchDir()), assertDatabaseReady()]);
    await projectRepository.initialize();
    await cleanupAbandonedCompilerOutputs();
    await checkPreparedCompiler();
    lifecycle.recoveredOperations = await projectOperationExecutor.recoverInterrupted();
    projectOperationExecutor.startRecovery();
    delete lifecycle.error;
    lifecycle.initialized = true;
  } catch (error) {
    lifecycle.error = error instanceof Error ? error.message : String(error);
    throw error;
  }
}

async function assertDatabaseReady() {
  await sqlClient().unsafe('select 1');
}

async function databaseReadinessError() {
  try {
    await assertDatabaseReady();
    return undefined;
  } catch (cause) {
    return cause instanceof Error ? cause.message : String(cause);
  }
}

async function checkPreparedCompiler() {
  try {
    const prepared = await visualizationService.readiness();
    lifecycle.compiler = {
      sourceSha256: prepared.sourceSha256,
      preparedAt: prepared.preparedAt
    };
    lifecycle.compilerCheckedAt = Date.now();
    if (lifecycle.initialized) delete lifecycle.error;
  } catch (error) {
    lifecycle.compilerCheckedAt = Date.now();
    lifecycle.error = error instanceof Error ? error.message : String(error);
    if (!lifecycle.initialized) throw error;
  }
}

async function assertWritableDirectory(directory: string) {
  await mkdir(directory, { recursive: true });
  const temporary = path.join(directory, `.write-probe.${randomUUID()}.tmp`);
  const published = path.join(directory, `.write-probe.${randomUUID()}`);
  const handle = await open(temporary, 'wx');
  try {
    await handle.writeFile('sverlin\n');
    await handle.sync();
  } finally {
    await handle.close();
  }
  try {
    await rename(temporary, published);
  } finally {
    await Promise.all([rm(temporary, { force: true }), rm(published, { force: true })]);
  }
}

async function cleanupAbandonedCompilerOutputs() {
  const scratch = runtimeScratchDir();
  const seeds = await readdir(scratch, { withFileTypes: true });
  for (const seed of seeds) {
    if (!seed.isDirectory() || !/^seed-[1-9][0-9]*$/.test(seed.name)) continue;
    const seedDirectory = path.join(scratch, seed.name);
    const entries = await readdir(seedDirectory, { withFileTypes: true });
    await Promise.all(
      entries
        .filter((entry) => entry.isDirectory() && entry.name.startsWith('visualization-service-'))
        .map((entry) => rm(path.join(seedDirectory, entry.name), { recursive: true, force: true }))
    );
  }
}

function compilerCheckIntervalMs() {
  const configured = Number(process.env.SVERLIN_COMPILER_HEALTH_INTERVAL_MS ?? '30000');
  return Number.isSafeInteger(configured) && configured >= 1_000 ? configured : 30_000;
}

function shutdownTimeoutMs(): number {
  const seconds = Number(process.env.SVERLIN_SHUTDOWN_TIMEOUT_SECONDS ?? '270');
  return (Number.isSafeInteger(seconds) && seconds >= 1 ? seconds : 270) * 1_000;
}
