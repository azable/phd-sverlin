/** Persistent, repository-local application maintenance lock. */

import { randomUUID } from 'node:crypto';
import { mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';

const schemaVersion = 1;

/** @typedef {{ locked: false } | { locked: true, lockedAt: string, reason?: string }} MaintenanceStatus */

/** Return the configured lock path, resolving relative overrides from the repository root. */
export function maintenanceLockPath(root = process.cwd()) {
  const configured = process.env.SVERLIN_APP_LOCK_PATH?.trim();
  return configured
    ? path.resolve(root, configured)
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
    await writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`, { flag: 'wx' });
    await rename(temporary, lockPath);
  } finally {
    await rm(temporary, { force: true });
  }
  return readMaintenanceStatus(lockPath);
}

/** Disable maintenance mode. */
export async function clearMaintenanceLock(lockPath = maintenanceLockPath()) {
  await rm(lockPath, { force: true });
  return { locked: false };
}

/** @param {string} reason @returns {MaintenanceStatus} */
function invalidLockStatus(reason) {
  return { locked: true, lockedAt: new Date(0).toISOString(), reason };
}
