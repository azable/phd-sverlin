/** Process lifecycle, readiness, and crash recovery for the packaged Svelte server. */

import { randomUUID } from 'node:crypto';
import { mkdir, open, readdir, rename, rm } from 'node:fs/promises';
import path from 'node:path';

import { validateAuthenticationConfiguration } from '$lib/server/auth';
import { clearPrefetches } from '$lib/server/compiler/prefetch';
import { readPreparedCompiler } from '$lib/server/compiler/prepared-compiler.js';
import { compilerScheduler, type CompileSchedulerStatus } from '$lib/server/compiler/scheduler';
import { sqlClient } from '$lib/server/db';
import { projectRepository, usesPostgresProjectStore } from '$lib/server/projects/repository';
import { recoveryEventsForInterruptedOperations } from '$lib/server/projects/recovery';

import { runtimeProjectDir, runtimeScratchDir } from './runtime-config';

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
  scheduler: CompileSchedulerStatus;
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

/** Stop speculative work and reject new compiles after HTTP request draining begins. */
export function shutdownRuntime(): void {
  lifecycle.draining = true;
  clearPrefetches();
  compilerScheduler.shutdown();
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
  const databaseError = usesPostgresProjectStore ? await databaseReadinessError() : undefined;
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
    scheduler: compilerScheduler.status()
  };
}

async function initializeRuntimeOnce() {
  try {
    validateAuthenticationConfiguration();
    await Promise.all([
      assertWritableDirectory(runtimeScratchDir()),
      ...(!usesPostgresProjectStore ? [assertWritableDirectory(runtimeProjectDir())] : []),
      ...(usesPostgresProjectStore ? [assertDatabaseReady()] : [])
    ]);
    await projectRepository.initialize();
    await cleanupAbandonedCompilerOutputs();
    await checkPreparedCompiler();
    // PostgreSQL jobs survive web and worker process restarts and own their own
    // lease recovery. File-backed development remains process-local.
    lifecycle.recoveredOperations = usesPostgresProjectStore
      ? 0
      : await recoverInterruptedOperations();
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
    const prepared = await readPreparedCompiler();
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
        .filter(
          (entry) =>
            entry.isDirectory() &&
            (entry.name.startsWith('project-') || entry.name.startsWith('prefetch-'))
        )
        .map((entry) => rm(path.join(seedDirectory, entry.name), { recursive: true, force: true }))
    );
  }
}

async function recoverInterruptedOperations() {
  const summaries = await projectRepository.list();
  let recovered = 0;
  for (const summary of summaries) {
    try {
      const document = await projectRepository.load(summary.projectId);
      const recoveryEvents = recoveryEventsForInterruptedOperations(document.events);
      if (recoveryEvents.length === 0) continue;
      await projectRepository.append(
        document.projectId,
        document.events.at(-1)?.id ?? 0,
        recoveryEvents
      );
      recovered += recoveryEvents.length;
    } catch (error) {
      lifecycle.warnings.push(
        `Could not recover project ${summary.projectId}: ${
          error instanceof Error ? error.message : String(error)
        }`
      );
    }
  }
  return recovered;
}

function compilerCheckIntervalMs() {
  const configured = Number(process.env.SVERLIN_COMPILER_HEALTH_INTERVAL_MS ?? '30000');
  return Number.isSafeInteger(configured) && configured >= 1_000 ? configured : 30_000;
}
