/** Environment-neutral server paths shared by development and packaged deployment. */

import path from 'node:path';

/** Absolute repository/application root. Packaged containers use a fixed work directory. */
export function runtimeRoot(): string {
  return path.resolve(process.env.SVERLIN_REPOSITORY_ROOT?.trim() || process.cwd());
}

/** Writable process state root, excluding disposable compiler scratch output. */
export function runtimeStateDir(): string {
  const configured = process.env.SVERLIN_STATE_DIR?.trim();
  return configured
    ? path.resolve(configured)
    : path.join(runtimeRoot(), '.local', 'state', 'sverlin');
}

/** Durable project Timeline directory with backward compatibility for existing checkouts. */
export function runtimeProjectDir(): string {
  const configured = process.env.SVERLIN_PROJECT_DIR?.trim();
  if (configured) return path.resolve(configured);
  if (process.env.SVERLIN_STATE_DIR?.trim()) return path.join(runtimeStateDir(), 'projects');
  return path.join(runtimeRoot(), 'data', 'projects');
}

/** Disposable compiler workspace root. */
export function runtimeScratchDir(): string {
  const configured =
    process.env.SVERLIN_SCRATCH_DIR?.trim() || process.env.SVERLIN_OUTPUT_DIR?.trim();
  return configured ? path.resolve(configured) : path.join(runtimeRoot(), 'outputs');
}
