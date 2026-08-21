import { randomUUID } from 'node:crypto';
import { rename, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';

export const dslSourcePath = 'compile/app/DSL/Main.sverlin' as const;

/** Persist the canonical Sverlin body without exposing a partial write. */
export async function persistSourceArtifact(
  content: string,
  sourceFile = path.resolve(process.cwd(), dslSourcePath)
) {
  const temporaryFile = path.join(
    path.dirname(sourceFile),
    `.${path.basename(sourceFile)}.${randomUUID()}.tmp`
  );

  try {
    await writeFile(temporaryFile, content, { encoding: 'utf8', flag: 'wx' });
    await rename(temporaryFile, sourceFile);
  } finally {
    await rm(temporaryFile, { force: true });
  }
}
