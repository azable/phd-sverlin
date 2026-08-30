/** Run a command against a migrated, uniquely named PostgreSQL test database. */

import { randomUUID } from 'node:crypto';
import { spawn } from 'node:child_process';

import postgres from 'postgres';

const arguments_ = process.argv.slice(2);
const seedAdmin = arguments_[0] === '--seed-admin';
if (seedAdmin) arguments_.shift();
if (arguments_.length === 0) throw new Error('A test command is required.');

const baseUrl = new URL(
  process.env.DATABASE_URL?.trim() || 'postgres://postgres:postgres@127.0.0.1:5432/sverlin'
);
const databaseName = `sverlin_test_${randomUUID().replaceAll('-', '')}`;
if (!/^sverlin_test_[a-f0-9]{32}$/.test(databaseName)) {
  throw new Error('Refusing to create an unvalidated test database name.');
}
const adminUrl = new URL(baseUrl);
adminUrl.pathname = '/postgres';
const testUrl = new URL(baseUrl);
testUrl.pathname = `/${databaseName}`;

const admin = postgres(adminUrl.toString(), { max: 1, prepare: false });
let child;
try {
  await admin.unsafe(`create database "${databaseName}"`);
  await run('pnpm', ['run', 'db:migrate'], { DATABASE_URL: testUrl.toString() });
  if (seedAdmin) {
    await run('pnpm', ['exec', 'tsx', 'scripts/seed-e2e.ts'], {
      DATABASE_URL: testUrl.toString()
    });
  }
  child = spawn(arguments_[0], arguments_.slice(1), {
    stdio: 'inherit',
    env: { ...process.env, DATABASE_URL: testUrl.toString() }
  });
  const forward = (signal) => child?.kill(signal);
  process.once('SIGINT', forward);
  process.once('SIGTERM', forward);
  const result = await exitResult(child);
  process.removeListener('SIGINT', forward);
  process.removeListener('SIGTERM', forward);
  process.exitCode = result;
} finally {
  child?.kill('SIGTERM');
  await admin`
    select pg_terminate_backend(pid)
    from pg_stat_activity
    where datname = ${databaseName} and pid <> pg_backend_pid()
  `.catch(() => undefined);
  await admin.unsafe(`drop database if exists "${databaseName}" with (force)`);
  await admin.end({ timeout: 5 });
}

async function run(command, arguments_, environment) {
  const child = spawn(command, arguments_, {
    stdio: 'inherit',
    env: { ...process.env, ...environment }
  });
  const code = await exitResult(child);
  if (code !== 0) throw new Error(`${command} exited with code ${code}.`);
}

function exitResult(process_) {
  return new Promise((resolve, reject) => {
    process_.once('error', reject);
    process_.once('exit', (code, signal) => resolve(code ?? (signal ? 1 : 0)));
  });
}
