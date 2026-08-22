/** Shared output-path allocation used by server compilation and Node scripts. */

import { mkdir, mkdtemp } from 'node:fs/promises';
import path from 'node:path';

const workspaceOutputDirEnvVar = 'SVERLIN_OUTPUT_DIR';
const defaultWorkspaceOutputDir = 'outputs';

/**
 * Return the absolute workspace directory for generated compiler outputs.
 *
 * @returns {string}
 */
export function readWorkspaceOutputDir() {
  const configuredDir = process.env[workspaceOutputDirEnvVar]?.trim();
  return configuredDir
    ? path.resolve(configuredDir)
    : path.join(process.cwd(), defaultWorkspaceOutputDir);
}

/**
 * Create and return the configured compiler output directory.
 *
 * @returns {Promise<string>}
 */
export async function ensureWorkspaceOutputDir() {
  const outputDir = readWorkspaceOutputDir();
  await mkdir(outputDir, { recursive: true });
  return outputDir;
}

/**
 * Allocate an isolated output directory for one compiler invocation.
 *
 * @param {{ owner: string, seed: number }} options
 * @returns {Promise<{ outputDir: string, outputPath: string }>}
 */
export async function createCompileOutput(options) {
  assertPositiveSeed(options.seed);

  const outputDir = await mkdtemp(
    path.join(
      await ensureSeedWorkspaceOutputDir(options.seed),
      `${outputOwnerLabel(options.owner)}-`
    )
  );

  return {
    outputDir,
    outputPath: path.join(outputDir, compiledVisualizationFileName(options.seed))
  };
}

/**
 * Return the deterministic visualization filename for a seed.
 *
 * @param {number} seed
 * @returns {string}
 */
export function compiledVisualizationFileName(seed) {
  assertPositiveSeed(seed);

  return `compiled-seed-${seed}.json`;
}

/**
 * Return the workspace subdirectory name shared by outputs for a seed.
 *
 * @param {number} seed
 * @returns {string}
 */
export function seedWorkspaceOutputDirName(seed) {
  assertPositiveSeed(seed);

  return `seed-${seed}`;
}

/**
 * @param {number} seed
 */
async function ensureSeedWorkspaceOutputDir(seed) {
  const outputDir = path.join(await ensureWorkspaceOutputDir(), seedWorkspaceOutputDirName(seed));
  await mkdir(outputDir, { recursive: true });
  return outputDir;
}

/**
 * @param {string} owner
 */
function outputOwnerLabel(owner) {
  const label = owner
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');

  return label || 'compile';
}

/**
 * @param {number} seed
 */
function assertPositiveSeed(seed) {
  if (!Number.isSafeInteger(seed) || seed <= 0) {
    throw new Error(`Seed must be a positive integer: ${seed}`);
  }
}
