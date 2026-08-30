#!/usr/bin/env node

import { spawn } from 'node:child_process';
import { readFile, rename, unlink, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { format, resolveConfig } from 'prettier';

const repositoryRoot = fileURLToPath(new URL('..', import.meta.url));
const outputPath = path.join(
  repositoryRoot,
  'src/lib/shared/visualization/generated/visualization-ir.ts'
);
const mode = process.argv[2];

if (!['--check', '--write'].includes(mode) || process.argv.length !== 3) {
  console.error('Usage: node scripts/visualization-types.mjs --check|--write');
  process.exit(64);
}

await runStack(['build', 'compile:visualization-types', '--jobs=1']);
const generated = await runStack(['exec', 'visualization-types'], true);
const prettierConfig = (await resolveConfig(outputPath)) ?? {};
const formatted = await format(generated, { ...prettierConfig, filepath: outputPath });

if (mode === '--check') {
  const current = await readFile(outputPath, 'utf8');
  if (current !== formatted) {
    console.error('Visualization types are stale; run `pnpm run generate:visualization-types`.');
    process.exit(1);
  }
  console.log('Visualization types are current.');
} else {
  const temporaryPath = `${outputPath}.${process.pid}.tmp`;
  try {
    await writeFile(temporaryPath, formatted);
    await rename(temporaryPath, outputPath);
  } finally {
    await unlink(temporaryPath).catch((error) => {
      if (error.code !== 'ENOENT') throw error;
    });
  }
  console.log(`Updated ${path.relative(repositoryRoot, outputPath)}.`);
}

function runStack(args, captureStdout = false) {
  return new Promise((resolve, reject) => {
    const child = spawn('stack', ['--stack-yaml', 'compile/stack.yaml', ...args], {
      cwd: repositoryRoot,
      env: process.env,
      stdio: ['ignore', captureStdout ? 'pipe' : 'inherit', 'inherit']
    });
    let stdout = '';
    child.stdout?.setEncoding('utf8');
    child.stdout?.on('data', (chunk) => {
      stdout += chunk;
    });
    child.on('error', reject);
    child.on('close', (code, signal) => {
      if (code === 0) resolve(stdout);
      else reject(new Error(`stack exited with ${code ?? signal ?? 'unknown status'}.`));
    });
  });
}
