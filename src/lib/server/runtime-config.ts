/** Environment-neutral server paths shared by development and packaged deployment. */

import path from 'node:path';

/** Absolute repository/application root. Packaged containers use a fixed work directory. */
export function runtimeRoot(): string {
  return path.resolve(process.env.SVERLIN_REPOSITORY_ROOT?.trim() || process.cwd());
}

/** Persistent local state shared with the single-server guard. */
export function runtimeStateDir(): string {
  return path.resolve(
    process.env.SVERLIN_STATE_DIR?.trim() || path.join(runtimeRoot(), '.local', 'state', 'sverlin')
  );
}
