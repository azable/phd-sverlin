import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { promisify } from 'node:util';

import type { DslRevision } from '$lib/projects/types';

const execFileAsync = promisify(execFile);
const choreographyDirectory = 'compile/src/LinearTrace/Choreography';
const dslSourcePaths = ['compile/src/LinearTrace/Choreography.hs', 'compile/app/Sverlin/Source.hs'];
const dslGitPaths = [...dslSourcePaths, choreographyDirectory];

export function sourceSha256(content: string) {
  return createHash('sha256').update(content).digest('hex');
}

export async function readDslRevision(): Promise<DslRevision | undefined> {
  try {
    const sourcePaths = await listDslSourcePaths();
    const contentSha256 = await hashFiles(sourcePaths);
    const git = await readGitRevision();
    return { contentSha256, ...git };
  } catch (error) {
    console.error('Could not identify the Sverlin DSL revision.', error);
    return undefined;
  }
}

async function listDslSourcePaths() {
  const modules = (await readdir(path.resolve(process.cwd(), choreographyDirectory)))
    .filter((file) => file.endsWith('.hs'))
    .sort()
    .map((file) => path.join(choreographyDirectory, file));
  return [...dslSourcePaths, ...modules];
}

async function hashFiles(sourcePaths: string[]) {
  const contents = await Promise.all(
    sourcePaths.map(async (sourcePath) => {
      const content = await readFile(path.resolve(process.cwd(), sourcePath), 'utf8');
      return `${sourcePath}\0${content}`;
    })
  );
  return sourceSha256(contents.join('\0'));
}

async function readGitRevision(): Promise<Omit<DslRevision, 'contentSha256'>> {
  try {
    const cwd = process.cwd();
    const [{ stdout: commit }, { stdout: status }] = await Promise.all([
      execFileAsync('git', ['rev-parse', '--verify', 'HEAD'], { cwd }),
      execFileAsync(
        'git',
        ['status', '--porcelain=v1', '--untracked-files=normal', '--', ...dslGitPaths],
        { cwd }
      )
    ]);
    return {
      repositoryCommit: commit.trim(),
      workingTree: status.trim() ? 'dirty' : 'clean'
    };
  } catch {
    return { workingTree: 'unknown' };
  }
}
