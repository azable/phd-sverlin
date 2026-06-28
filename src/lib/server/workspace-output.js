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
 * @param {string} prefix
 */
export async function mkdtempInWorkspaceOutputs(prefix) {
  return mkdtemp(path.join(await ensureWorkspaceOutputDir(), prefix));
}
