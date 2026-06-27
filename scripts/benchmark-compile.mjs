#!/usr/bin/env node

import { spawn } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { performance } from 'node:perf_hooks';

const defaultSeeds = [1, 320994595, -1988735004, 1731275846, 1999326623];

const options = parseArgs(process.argv.slice(2));

if (options.help) {
  printHelp();
  process.exit(0);
}

const repoRoot = process.cwd();
const command = path.join(repoRoot, 'compile.sh');
const startedAt = new Date().toISOString();

for (let i = 0; i < options.warmup; i += 1) {
  const seed = options.seeds[i % options.seeds.length];
  await runCompile({
    command,
    cwd: repoRoot,
    seed,
    details: options.details,
    timeoutMs: options.timeoutMs
  });
}

const runs = [];
for (let iteration = 1; iteration <= options.iterations; iteration += 1) {
  for (const seed of options.seeds) {
    const run = await runCompile({
      command,
      cwd: repoRoot,
      seed,
      details: options.details,
      timeoutMs: options.timeoutMs
    });
    runs.push({ iteration, ...run });
    printRun(run, iteration);
  }
}

const summary = summarize(runs);
printSummary(summary);

const result = {
  startedAt,
  finishedAt: new Date().toISOString(),
  command: './compile.sh',
  mode: options.details ? 'json+details' : 'json',
  options: {
    seeds: options.seeds,
    iterations: options.iterations,
    warmup: options.warmup,
    timeoutMs: options.timeoutMs,
    details: options.details
  },
  summary,
  runs
};

if (options.output) {
  await mkdir(path.dirname(path.resolve(options.output)), { recursive: true });
  await writeFile(options.output, `${JSON.stringify(result, null, 2)}\n`, 'utf8');
  console.log(`\nWrote benchmark results to ${options.output}`);
}

if (summary.failureCount > 0) {
  process.exitCode = 1;
}

function parseArgs(args) {
  const parsed = {
    details: false,
    help: false,
    iterations: 1,
    output: null,
    seeds: defaultSeeds,
    timeoutMs: 20_000,
    warmup: 1
  };

  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];
    switch (arg) {
      case '--':
        break;
      case '--details':
        parsed.details = true;
        break;
      case '--help':
      case '-h':
        parsed.help = true;
        break;
      case '--iterations':
        parsed.iterations = positiveInt(nextValue(args, ++i, arg), arg);
        break;
      case '--output':
        parsed.output = nextValue(args, ++i, arg);
        break;
      case '--seed':
      case '--seeds':
        parsed.seeds = parseSeeds(nextValue(args, ++i, arg));
        break;
      case '--timeout-ms':
        parsed.timeoutMs = positiveInt(nextValue(args, ++i, arg), arg);
        break;
      case '--warmup':
        parsed.warmup = nonNegativeInt(nextValue(args, ++i, arg), arg);
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return parsed;
}

function nextValue(args, index, flag) {
  const value = args[index];
  if (!value || value.startsWith('--')) {
    throw new Error(`${flag} requires a value`);
  }
  return value;
}

function positiveInt(value, flag) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error(`${flag} must be a positive integer`);
  }
  return parsed;
}

function nonNegativeInt(value, flag) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isInteger(parsed) || parsed < 0) {
    throw new Error(`${flag} must be a non-negative integer`);
  }
  return parsed;
}

function parseSeeds(value) {
  const seeds = value
    .split(',')
    .map((seed) => seed.trim())
    .filter(Boolean)
    .map((seed) => Number.parseInt(seed, 10));

  if (seeds.length === 0 || seeds.some((seed) => !Number.isInteger(seed))) {
    throw new Error('--seed must be a comma-separated list of integers');
  }

  return seeds;
}

function runCompile({ command, cwd, seed, details, timeoutMs }) {
  return new Promise((resolve) => {
    const args = ['--json', '--seed', String(seed)];
    if (details) {
      args.push('--details');
    }

    const started = performance.now();
    const child = spawn(command, args, {
      cwd,
      stdio: ['ignore', 'pipe', 'pipe']
    });

    let stdout = '';
    let stderr = '';
    let settled = false;
    let timedOut = false;

    const timer = setTimeout(() => {
      timedOut = true;
      child.kill('SIGTERM');
    }, timeoutMs);

    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');

    child.stdout.on('data', (chunk) => {
      stdout += chunk;
    });

    child.stderr.on('data', (chunk) => {
      stderr += chunk;
    });

    child.on('error', (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(finishRun({ seed, args, started, stdout, stderr, timedOut, exitCode: null, error }));
    });

    child.on('close', (exitCode) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(finishRun({ seed, args, started, stdout, stderr, timedOut, exitCode }));
    });
  });
}

function finishRun({ seed, args, started, stdout, stderr, timedOut, exitCode, error }) {
  const durationMs = performance.now() - started;
  let jsonOk = false;
  let parseError = null;

  if (!error && exitCode === 0 && !timedOut) {
    try {
      JSON.parse(stdout);
      jsonOk = true;
    } catch (err) {
      parseError = err instanceof Error ? err.message : String(err);
    }
  }

  return {
    seed,
    args,
    durationMs,
    exitCode,
    timedOut,
    ok: !error && exitCode === 0 && !timedOut && jsonOk,
    jsonOk,
    stdoutBytes: Buffer.byteLength(stdout, 'utf8'),
    stderrBytes: Buffer.byteLength(stderr, 'utf8'),
    error: error ? error.message : null,
    parseError
  };
}

function summarize(runs) {
  const successful = runs.filter((run) => run.ok);
  const durations = successful.map((run) => run.durationMs);

  return {
    runCount: runs.length,
    successCount: successful.length,
    failureCount: runs.length - successful.length,
    durationMs: stats(durations)
  };
}

function stats(values) {
  if (values.length === 0) {
    return { min: null, mean: null, median: null, p95: null, max: null };
  }

  const sorted = [...values].sort((a, b) => a - b);
  const sum = sorted.reduce((acc, value) => acc + value, 0);
  const p95Index = Math.max(0, Math.ceil(sorted.length * 0.95) - 1);

  return {
    min: sorted[0],
    mean: sum / sorted.length,
    median: percentile(sorted, 0.5),
    p95: sorted[p95Index],
    max: sorted[sorted.length - 1]
  };
}

function percentile(sortedValues, p) {
  if (sortedValues.length === 1) {
    return sortedValues[0];
  }

  const index = (sortedValues.length - 1) * p;
  const lower = Math.floor(index);
  const upper = Math.ceil(index);
  const weight = index - lower;
  return sortedValues[lower] * (1 - weight) + sortedValues[upper] * weight;
}

function printRun(run, iteration) {
  const status = run.ok ? 'ok' : run.timedOut ? 'timeout' : 'fail';
  console.log(
    [
      `iter=${iteration}`,
      `seed=${run.seed}`,
      `status=${status}`,
      `duration=${formatMs(run.durationMs)}`,
      `stdout=${run.stdoutBytes}`,
      `stderr=${run.stderrBytes}`
    ].join(' ')
  );

  if (!run.ok) {
    const reason = run.error || run.parseError || `exitCode=${run.exitCode}`;
    console.log(`  reason=${reason}`);
  }
}

function printSummary(summary) {
  const durations = summary.durationMs;

  console.log('\nCompile benchmark summary');
  console.log('-------------------------');
  console.log(`runs:     ${summary.runCount}`);
  console.log(`success:  ${summary.successCount}`);
  console.log(`failures: ${summary.failureCount}`);
  console.log(`min:      ${formatNullableMs(durations.min)}`);
  console.log(`mean:     ${formatNullableMs(durations.mean)}`);
  console.log(`median:   ${formatNullableMs(durations.median)}`);
  console.log(`p95:      ${formatNullableMs(durations.p95)}`);
  console.log(`max:      ${formatNullableMs(durations.max)}`);
}

function formatNullableMs(value) {
  return value === null ? 'n/a' : formatMs(value);
}

function formatMs(value) {
  return `${value.toFixed(1)}ms`;
}

function printHelp() {
  console.log(`Usage: pnpm run bench:compile -- [options]

Options:
  --iterations N    Runs per seed. Default: 1
  --warmup N        Warmup invocations before measurement. Default: 1
  --timeout-ms N    Per-run timeout. Default: 20000
  --seed A,B,C      Override default seed list
  --output PATH     Write full JSON results
  --details         Include compile backend --details diagnostics
  --help            Show this message
`);
}
