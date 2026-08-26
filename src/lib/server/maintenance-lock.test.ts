import { chmod, mkdtemp, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

import { afterEach, describe, expect, it } from 'vitest';

import {
  clearMaintenanceLock,
  readMaintenanceStatus,
  writeMaintenanceLock
} from './maintenance-lock.js';

const roots: string[] = [];

afterEach(async () => {
  const { rm } = await import('node:fs/promises');
  await Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true })));
});

describe('maintenance lock', () => {
  it('persists an explicit lock until it is explicitly cleared', async () => {
    const lockPath = await temporaryLockPath();
    const locked = await writeMaintenanceLock('Compiler maintenance', lockPath);

    expect(locked).toMatchObject({ locked: true, reason: 'Compiler maintenance' });
    expect(await readMaintenanceStatus(lockPath)).toEqual(locked);
    expect(await clearMaintenanceLock(lockPath)).toEqual({ locked: false });
    expect(await readMaintenanceStatus(lockPath)).toEqual({ locked: false });
  });

  it('fails closed when a lock exists but is malformed', async () => {
    const lockPath = await temporaryLockPath();
    await writeFile(lockPath, '{not-json', 'utf8');

    expect(await readMaintenanceStatus(lockPath)).toMatchObject({
      locked: true,
      reason: 'The maintenance lock is malformed.'
    });
  });
});

async function temporaryLockPath(): Promise<string> {
  const root = await mkdtemp(path.join(tmpdir(), 'sverlin-maintenance-test-'));
  roots.push(root);
  await chmod(root, 0o700);
  return path.join(root, 'app-lock.json');
}
