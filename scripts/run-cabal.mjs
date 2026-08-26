#!/usr/bin/env node

import { spawn } from 'node:child_process';
import { cabalConfig, cabalEnvironment, compileRoot } from './compiler-environment.mjs';

const child = spawn('cabal', [`--config-file=${cabalConfig}`, ...process.argv.slice(2)], {
  cwd: compileRoot,
  detached: process.platform !== 'win32',
  env: cabalEnvironment,
  stdio: 'inherit'
});

const forwardedSignals = ['SIGINT', 'SIGTERM'].map((signal) => ({
  signal,
  handler: () => terminate(child.pid, signal)
}));

for (const { signal, handler } of forwardedSignals) {
  process.once(signal, handler);
}

child.on('error', (error) => {
  console.error(error);
  process.exitCode = 1;
});

child.on('close', (exitCode, signal) => {
  for (const forwardedSignal of forwardedSignals) {
    process.removeListener(forwardedSignal.signal, forwardedSignal.handler);
  }

  process.exitCode = exitCode ?? signalExitCode(signal);
});

function terminate(pid, signal) {
  if (pid === undefined) return;

  try {
    process.kill(process.platform === 'win32' ? pid : -pid, signal);
  } catch {
    try {
      process.kill(pid, signal);
    } catch {
      // The process may already have exited between the forwarded signal and kill.
    }
  }
}

function signalExitCode(signal) {
  if (signal === 'SIGINT') return 130;
  if (signal === 'SIGTERM') return 143;
  return 1;
}
