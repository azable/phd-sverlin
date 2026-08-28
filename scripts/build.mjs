#!/usr/bin/env node

import { spawn } from 'node:child_process';

await run('pnpm', ['run', 'prepare:compiler']);
await run('pnpm', ['exec', 'vite', 'build']);
await run('pnpm', ['run', 'build:migrate']);
await run('pnpm', ['run', 'build:worker']);

function run(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: 'inherit', env: process.env });
    child.on('error', reject);
    child.on('close', (code, signal) => {
      if (code === 0) resolve();
      else reject(new Error(`${command} exited with ${code ?? signal ?? 'unknown status'}.`));
    });
  });
}
