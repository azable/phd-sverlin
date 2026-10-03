import { execFileSync } from 'node:child_process';
import { copyFile, mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

describe('server launch environment', () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(path.join(tmpdir(), 'sverlin-launch-'));
    await mkdir(path.join(root, 'scripts'));
    for (const script of ['load-env.sh', 'run-with-env.sh']) {
      await copyFile(path.resolve('scripts', script), path.join(root, 'scripts', script));
    }
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  function launch(environment: Record<string, string> = {}) {
    const env = { ...process.env };
    for (const key of [
      'OPENAI_API_KEY',
      'DEVENV_ROOT',
      'DATABASE_URL',
      'BETTER_AUTH_SECRET',
      'BETTER_AUTH_URL',
      'BETTER_AUTH_TRUSTED_ORIGINS'
    ]) {
      delete env[key];
    }
    Object.assign(env, environment);
    return JSON.parse(
      execFileSync(
        'bash',
        [
          path.join(root, 'scripts/run-with-env.sh'),
          process.execPath,
          '-e',
          'console.log(JSON.stringify({ key: process.env.OPENAI_API_KEY, database: process.env.DATABASE_URL, secret: process.env.BETTER_AUTH_SECRET }))'
        ],
        { cwd: tmpdir(), env, encoding: 'utf8' }
      )
    );
  }

  it('reloads the file on every launch despite a stale parent environment', async () => {
    await writeFile(path.join(root, '.env'), 'OPENAI_API_KEY="first test key"\n');
    expect(launch({ OPENAI_API_KEY: '' }).key).toBe('first test key');

    await writeFile(path.join(root, '.env'), 'OPENAI_API_KEY="updated test key"\n');
    expect(launch({ OPENAI_API_KEY: 'stale test key' }).key).toBe('updated test key');
  });

  it('preserves development defaults for blank optional settings', async () => {
    await writeFile(path.join(root, '.env'), 'DATABASE_URL=\nBETTER_AUTH_SECRET=\n');
    expect(launch({ DEVENV_ROOT: root, PGPORT: '6543' })).toEqual({
      database: 'postgres://sverlin:sverlin@127.0.0.1:6543/sverlin',
      secret: 'development-only-secret-at-least-32-bytes'
    });
  });

  it('honors explicit settings and clearing a previously configured key', async () => {
    await writeFile(
      path.join(root, '.env'),
      'OPENAI_API_KEY=\nDATABASE_URL="postgres://test:test@localhost/custom"\nBETTER_AUTH_SECRET="explicit test secret"\n'
    );
    expect(launch({ DEVENV_ROOT: root, OPENAI_API_KEY: 'stale test key' })).toEqual({
      key: '',
      database: 'postgres://test:test@localhost/custom',
      secret: 'explicit test secret'
    });
  });

  it('uses inherited production configuration when there is no .env', () => {
    expect(
      launch({ OPENAI_API_KEY: 'inherited test key', DATABASE_URL: 'inherited database' })
    ).toEqual({
      key: 'inherited test key',
      database: 'inherited database'
    });
  });

  it('does not add development credentials outside devenv', async () => {
    await writeFile(path.join(root, '.env'), 'OPENAI_API_KEY="production test key"\n');
    expect(launch()).toEqual({ key: 'production test key' });
  });
});
