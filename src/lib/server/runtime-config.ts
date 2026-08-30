/** Environment-neutral server paths shared by development and packaged deployment. */

import path from 'node:path';

/** Absolute repository/application root. Packaged containers use a fixed work directory. */
export function runtimeRoot(): string {
  return path.resolve(process.env.SVERLIN_REPOSITORY_ROOT?.trim() || process.cwd());
}

/** Disposable compiler workspace root. */
export function runtimeScratchDir(): string {
  const configured =
    process.env.SVERLIN_SCRATCH_DIR?.trim() || process.env.SVERLIN_OUTPUT_DIR?.trim();
  return configured ? path.resolve(configured) : path.join(runtimeRoot(), 'outputs');
}
