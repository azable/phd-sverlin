import { randomUUID } from 'node:crypto';
import { mkdir, open, readFile, rm } from 'node:fs/promises';
import path from 'node:path';

import { readWorkspaceOutputDir } from './workspace-output.js';

/** @typedef {'web' | 'manual' | 'bench' | string} CompileLockOwner */

/**
 * @typedef {object} CompileLockInfo
 * @property {string} token
 * @property {CompileLockOwner} owner
 * @property {number} pid
 * @property {string} startedAt
 * @property {string} cwd
 * @property {string} command
 * @property {string[]} args
 * @property {number=} seed
 * @property {string=} outputPath
 */

/**
 * @typedef {object} PublicCompileLockInfo
 * @property {CompileLockOwner} owner
 * @property {number} pid
 * @property {string} startedAt
 * @property {string} cwd
 * @property {string} command
 * @property {string[]} args
 * @property {number=} seed
 * @property {string=} outputPath
 * @property {string} lockPath
 */

/**
 * @typedef {object} CompileLockHandle
 * @property {string} path
 * @property {CompileLockInfo} info
 * @property {() => Promise<boolean>} release
 */

/**
 * @typedef {object} AcquireCompileLockOptions
 * @property {CompileLockOwner} owner
 * @property {string} cwd
 * @property {string} command
 * @property {string[]} args
 * @property {number=} seed
 * @property {string=} outputPath
 */

/**
 * @typedef {(
 *   | { acquired: true, lock: CompileLockHandle }
 *   | { acquired: false, lockPath: string, holder: PublicCompileLockInfo | null, message: string }
 * )} AcquireCompileLockResult
 */

const compileLockPathEnvVar = 'SVERLIN_COMPILE_LOCK_PATH';
const defaultLockFileName = 'sverlin-compile.lock';

/**
 * @param {AcquireCompileLockOptions} options
 * @returns {Promise<AcquireCompileLockResult>}
 */
export async function acquireCompileLock(options) {
  const lockPath = readCompileLockPath();
  await mkdir(path.dirname(lockPath), { recursive: true });

  for (let attempt = 0; attempt < 2; attempt += 1) {
    const info = buildCompileLockInfo(options);

    try {
      const file = await open(lockPath, 'wx');

      try {
        await file.writeFile(`${JSON.stringify(info, null, 2)}\n`, 'utf8');
      } finally {
        await file.close();
      }

      /** @type {CompileLockHandle} */
      const lock = {
        path: lockPath,
        info,
        release: async () => releaseCompileLock(lock)
      };

      return { acquired: true, lock };
    } catch (err) {
      if (!isNodeErrorCode(err, 'EEXIST')) {
        throw err;
      }

      const holder = await readCompileLock(lockPath);
      if (holder && !isProcessAlive(holder.pid)) {
        await removeLockIfTokenMatches(lockPath, holder.token);
        continue;
      }

      const publicHolder = publicCompileLockInfo(holder, lockPath);

      return {
        acquired: false,
        lockPath,
        holder: publicHolder,
        message: formatCompileLockBusyMessage(publicHolder, lockPath)
      };
    }
  }

  const holder = publicCompileLockInfo(await readCompileLock(lockPath), lockPath);

  return {
    acquired: false,
    lockPath,
    holder,
    message: formatCompileLockBusyMessage(holder, lockPath)
  };
}

/**
 * @param {CompileLockHandle} lock
 */
export async function releaseCompileLock(lock) {
  const current = await readCompileLock(lock.path);

  if (!current || current.token !== lock.info.token) {
    return false;
  }

  await rm(lock.path, { force: true });
  return true;
}

/**
 * @param {string=} lockPath
 * @returns {Promise<CompileLockInfo | null>}
 */
export async function readCompileLock(lockPath = readCompileLockPath()) {
  try {
    return parseCompileLockInfo(JSON.parse(await readFile(lockPath, 'utf8')));
  } catch (err) {
    if (isNodeErrorCode(err, 'ENOENT')) {
      return null;
    }

    return null;
  }
}

/**
 * @param {string=} lockPath
 * @returns {Promise<PublicCompileLockInfo | null>}
 */
export async function readActiveCompileLock(lockPath = readCompileLockPath()) {
  const lock = await readCompileLock(lockPath);
  if (!lock) return null;

  if (!isProcessAlive(lock.pid)) {
    await removeLockIfTokenMatches(lockPath, lock.token);
    return null;
  }

  return publicCompileLockInfo(lock, lockPath);
}

export function readCompileLockPath() {
  const configuredPath = process.env[compileLockPathEnvVar]?.trim();
  return configuredPath ? configuredPath : path.join(readWorkspaceOutputDir(), defaultLockFileName);
}

/**
 * @param {CompileLockInfo | null} info
 * @param {string=} lockPath
 * @returns {PublicCompileLockInfo | null}
 */
export function publicCompileLockInfo(info, lockPath = readCompileLockPath()) {
  if (!info) return null;

  return {
    owner: info.owner,
    pid: info.pid,
    startedAt: info.startedAt,
    cwd: info.cwd,
    command: info.command,
    args: info.args,
    ...(typeof info.seed === 'number' ? { seed: info.seed } : {}),
    ...(info.outputPath ? { outputPath: info.outputPath } : {}),
    lockPath
  };
}

/**
 * @param {PublicCompileLockInfo | null} holder
 * @param {string=} lockPath
 */
export function formatCompileLockBusyMessage(holder, lockPath = readCompileLockPath()) {
  if (!holder) {
    return `Compile backend is already running; lock file exists at ${lockPath}.`;
  }

  const command = [holder.command, ...holder.args].join(' ');
  return `Compile backend is already running (${holder.owner}, pid ${holder.pid}, started ${holder.startedAt}): ${command}`;
}

/**
 * @param {AcquireCompileLockOptions} options
 * @returns {CompileLockInfo}
 */
function buildCompileLockInfo(options) {
  return {
    token: randomUUID(),
    owner: options.owner,
    pid: process.pid,
    startedAt: new Date().toISOString(),
    cwd: options.cwd,
    command: options.command,
    args: options.args,
    ...(typeof options.seed === 'number' ? { seed: options.seed } : {}),
    ...(options.outputPath ? { outputPath: options.outputPath } : {})
  };
}

/**
 * @param {unknown} value
 * @returns {CompileLockInfo | null}
 */
function parseCompileLockInfo(value) {
  if (!value || typeof value !== 'object') return null;

  const record = /** @type {Record<string, unknown>} */ (value);
  const rawArgs = record.args;
  const args = Array.isArray(rawArgs) ? rawArgs.filter((arg) => typeof arg === 'string') : null;

  if (
    typeof record.token !== 'string' ||
    typeof record.owner !== 'string' ||
    typeof record.pid !== 'number' ||
    !Number.isInteger(record.pid) ||
    record.pid <= 0 ||
    typeof record.startedAt !== 'string' ||
    typeof record.cwd !== 'string' ||
    typeof record.command !== 'string' ||
    !args ||
    !Array.isArray(rawArgs) ||
    args.length !== rawArgs.length
  ) {
    return null;
  }

  return {
    token: record.token,
    owner: record.owner,
    pid: record.pid,
    startedAt: record.startedAt,
    cwd: record.cwd,
    command: record.command,
    args,
    ...(typeof record.seed === 'number' && Number.isSafeInteger(record.seed)
      ? { seed: record.seed }
      : {}),
    ...(typeof record.outputPath === 'string' ? { outputPath: record.outputPath } : {})
  };
}

/**
 * @param {string} lockPath
 * @param {string} token
 */
async function removeLockIfTokenMatches(lockPath, token) {
  const current = await readCompileLock(lockPath);

  if (current?.token === token) {
    await rm(lockPath, { force: true });
  }
}

/**
 * @param {number} pid
 */
function isProcessAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (err) {
    if (isNodeErrorCode(err, 'EPERM')) {
      return true;
    }

    return false;
  }
}

/**
 * @param {unknown} err
 * @param {string} code
 */
function isNodeErrorCode(err, code) {
  return err instanceof Error && 'code' in err && err.code === code;
}
