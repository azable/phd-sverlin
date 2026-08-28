/** Persistent, repository-local application maintenance lock. */

import { randomUUID } from 'node:crypto';
import { mkdir, open, readFile, rename, rm } from 'node:fs/promises';
import path from 'node:path';

const schemaVersion = 1;

/** @typedef {{ locked: false } | { locked: true, lockedAt: string, reason?: string }} MaintenanceStatus */

/** Return the configured lock path, resolving relative overrides from the repository root. */
export function maintenanceLockPath(root = process.cwd()) {
  const configured = process.env.SVERLIN_APP_LOCK_PATH?.trim();
  const stateDirectory = process.env.SVERLIN_STATE_DIR?.trim();
  return configured
    ? path.resolve(root, configured)
    : stateDirectory
      ? path.join(path.resolve(stateDirectory), 'app-lock.json')
      : path.join(root, '.cache', 'sverlin', 'app-lock.json');
}

/** Read the lock. Missing means unlocked; unreadable or malformed locks fail closed. */
/** @returns {Promise<MaintenanceStatus>} */
export async function readMaintenanceStatus(lockPath = maintenanceLockPath()) {
  let source;
  try {
    source = await readFile(lockPath, 'utf8');
  } catch (error) {
    if (error instanceof Error && 'code' in error && error.code === 'ENOENT') {
      return { locked: false };
    }
    return invalidLockStatus('The maintenance lock could not be read.');
  }

  try {
    const value = JSON.parse(source);
    if (
      value?.schemaVersion !== schemaVersion ||
      typeof value.lockedAt !== 'string' ||
      Number.isNaN(Date.parse(value.lockedAt)) ||
      (value.reason !== undefined && typeof value.reason !== 'string')
    ) {
      return invalidLockStatus('The maintenance lock is malformed.');
    }
    return {
      locked: true,
      lockedAt: value.lockedAt,
      ...(value.reason ? { reason: value.reason } : {})
    };
  } catch {
    return invalidLockStatus('The maintenance lock is malformed.');
  }
}

/** Atomically enable read-only maintenance mode. */
/** @param {string | undefined} reason @param {string} [lockPath] */
export async function writeMaintenanceLock(reason, lockPath = maintenanceLockPath()) {
  const value = {
    schemaVersion,
    lockedAt: new Date().toISOString(),
    ...(reason?.trim() ? { reason: reason.trim() } : {})
  };
  const temporary = `${lockPath}.${randomUUID()}.tmp`;
  await mkdir(path.dirname(lockPath), { recursive: true });
  try {
    const handle = await open(temporary, 'wx');
    try {
      await handle.writeFile(`${JSON.stringify(value, null, 2)}\n`);
      await handle.sync();
    } finally {
      await handle.close();
    }
    await rename(temporary, lockPath);
    await syncDirectory(path.dirname(lockPath));
  } finally {
    await rm(temporary, { force: true });
  }
  return readMaintenanceStatus(lockPath);
}

/** Disable maintenance mode. */
export async function clearMaintenanceLock(lockPath = maintenanceLockPath()) {
  await rm(lockPath, { force: true });
  await syncDirectory(path.dirname(lockPath));
  return { locked: false };
}

/** @param {string} directory */
async function syncDirectory(directory) {
  if (process.platform === 'win32') return;
  let handle;
  try {
    handle = await open(directory, 'r');
  } catch (error) {
    if (isUnsupportedDirectorySync(error)) return;
    throw error;
  }
  try {
    try {
      await handle.sync();
    } catch (error) {
      if (!isUnsupportedDirectorySync(error)) throw error;
    }
  } finally {
    await handle.close();
  }
}

/** @param {unknown} error */
function isUnsupportedDirectorySync(error) {
  return (
    error instanceof Error &&
    'code' in error &&
    (error.code === 'EINVAL' || error.code === 'ENOTSUP' || error.code === 'EBADF')
  );
}

/** @param {string} reason @returns {MaintenanceStatus} */
function invalidLockStatus(reason) {
  return { locked: true, lockedAt: new Date(0).toISOString(), reason };
}
