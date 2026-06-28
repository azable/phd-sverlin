import { mkdir, mkdtemp } from 'node:fs/promises';
import path from 'node:path';

const workspaceOutputDirEnvVar = 'SVERLIN_OUTPUT_DIR';
const defaultWorkspaceOutputDir = 'outputs';

export function readWorkspaceOutputDir() {
  const configuredDir = process.env[workspaceOutputDirEnvVar]?.trim();
  return configuredDir
    ? path.resolve(configuredDir)
    : path.join(process.cwd(), defaultWorkspaceOutputDir);
}

export async function ensureWorkspaceOutputDir() {
  const outputDir = readWorkspaceOutputDir();
  await mkdir(outputDir, { recursive: true });
  return outputDir;
}

/**
 * @param {{ owner: string, seed: number }} options
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
 * @param {number} seed
 */
export function compiledVisualizationFileName(seed) {
  assertPositiveSeed(seed);

  return `compiled-seed-${seed}.json`;
}

/**
 * @param {number} seed
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
