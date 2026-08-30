/** Start the Playwright web server, including its in-process operation executor. */

import { spawn } from 'node:child_process';

await runOnce('pnpm', ['run', 'prepare:compiler']);

const environment = {
  ...process.env,
  SVERLIN_SCRATCH_DIR: process.env.SVERLIN_SCRATCH_DIR || 'outputs/playwright/compiler',
  SVERLIN_E2E_AUTH_BYPASS: 'true',
  SVERLIN_SHUTDOWN_TIMEOUT_SECONDS: '10'
};
const children = [
  spawn(
    'node',
    [
      'scripts/run-with-state-lock.mjs',
      'node',
      'node_modules/vite/bin/vite.js',
      'dev',
      '--configLoader',
      'native',
      '--host',
      '127.0.0.1',
      '--port',
      '4173',
      '--strictPort'
    ],
    { stdio: 'inherit', env: environment }
  )
];

let stopping = false;
const stop = (signal = 'SIGTERM') => {
  if (stopping) return;
  stopping = true;
  for (const child of children) child.kill(signal);
};
process.once('SIGINT', () => stop('SIGINT'));
process.once('SIGTERM', () => stop('SIGTERM'));

const outcomes = await Promise.all(
  children.map(
    (child) =>
      new Promise((resolve, reject) => {
        child.once('error', reject);
        child.once('exit', (code, signal) => {
          if (!stopping) stop();
          resolve(code ?? (signal ? 0 : 1));
        });
      })
  )
);
process.exitCode = outcomes.find((code) => code !== 0) ?? 0;

async function runOnce(command, arguments_) {
  const child = spawn(command, arguments_, { stdio: 'inherit', env: process.env });
  const code = await new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('exit', (value) => resolve(value ?? 1));
  });
  if (code !== 0) throw new Error(`${command} exited with code ${code}.`);
}
