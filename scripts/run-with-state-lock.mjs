#!/usr/bin/env node

import { spawn } from 'node:child_process';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';

const command = process.argv[2];
const args = process.argv.slice(3);

if (!command) {
  console.error('Usage: node scripts/run-with-state-lock.mjs COMMAND [ARG...]');
  process.exit(64);
}

const repositoryRoot = path.resolve(process.env.SVERLIN_REPOSITORY_ROOT?.trim() || process.cwd());
const stateRoot = path.resolve(
  process.env.SVERLIN_STATE_DIR?.trim() || path.join(repositoryRoot, '.local', 'state', 'sverlin')
);
await mkdir(stateRoot, { recursive: true });

const stateLock = path.join(stateRoot, '.server.lock');
const child =
  process.platform === 'win32'
    ? spawn(command, args, childOptions())
    : spawn(
        'flock',
        [
          '--exclusive',
          '--nonblock',
          '--no-fork',
          '--conflict-exit-code',
          '73',
          stateLock,
          command,
          ...args
        ],
        childOptions()
      );

const forwardedSignals = ['SIGINT', 'SIGTERM'].map((signal) => {
  const handler = () => terminateTree(child.pid, signal);
  process.once(signal, handler);
  return { signal, handler };
});

child.on('error', (error) => {
  console.error(`Could not start ${command}: ${error.message}`);
  process.exitCode = 1;
});

child.on('close', (exitCode, signal) => {
  for (const forwarded of forwardedSignals) {
    process.removeListener(forwarded.signal, forwarded.handler);
  }
  if (exitCode === 73) {
    console.error(
      `Sverlin state is already owned by another server (${stateLock}). ` +
        'Stop it or configure a different SVERLIN_STATE_DIR.'
    );
  }
  process.exitCode = exitCode ?? signalExitCode(signal);
});

function childOptions() {
  return {
    cwd: repositoryRoot,
    detached: process.platform !== 'win32',
    env: process.env,
    stdio: 'inherit'
  };
}

function terminateTree(pid, signal) {
  if (pid === undefined) return;
  try {
    process.kill(process.platform === 'win32' ? pid : -pid, signal);
  } catch {
    try {
      process.kill(pid, signal);
    } catch {
      // The server may already have completed its graceful shutdown.
    }
  }
}

function signalExitCode(signal) {
  if (signal === 'SIGINT') return 130;
  if (signal === 'SIGTERM') return 143;
  return 1;
}
