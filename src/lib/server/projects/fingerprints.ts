import { createHash } from 'node:crypto';
import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';

const dslSourcePaths = ['compile/src/LinearTrace/Choreography.hs', 'compile/app/Sverlin/Source.hs'];
let dslApiFingerprint: Promise<string | undefined> | undefined;

export function sourceSha256(content: string) {
  return createHash('sha256').update(content).digest('hex');
}

export async function readDslApiFingerprint() {
  dslApiFingerprint ??= computeDslApiFingerprint().catch((error) => {
    console.error('Could not fingerprint the Sverlin DSL API.', error);
    return undefined;
  });
  return dslApiFingerprint;
}

async function computeDslApiFingerprint() {
  const choreographyDirectory = path.resolve(process.cwd(), 'compile/src/LinearTrace/Choreography');
  const choreographyModules = (await readdir(choreographyDirectory))
    .filter((file) => file.endsWith('.hs'))
    .sort()
    .map((file) => path.join('compile/src/LinearTrace/Choreography', file));
  const contents = await Promise.all(
    [...dslSourcePaths, ...choreographyModules].map(async (sourcePath) => {
      const content = await readFile(path.resolve(process.cwd(), sourcePath), 'utf8');
      return `${sourcePath}\0${content}`;
    })
  );
  return sourceSha256(contents.join('\0'));
}
