/**
 * Reproducible fingerprints for source text and the authored Sverlin contract.
 *
 * @packageDocumentation
 */

import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import { promisify } from 'node:util';

import type { DslRevision, RecordedText } from '$lib/shared/projects/events/values';
import {
  dslContractInputPaths,
  fingerprintRepositoryFiles
} from '$lib/server/repository-fingerprints.js';

const execFileAsync = promisify(execFile);

/** Calculate the lowercase SHA-256 digest for source text. */
export function sourceSha256(content: string): string {
  return createHash('sha256').update(content).digest('hex');
}

/** Embed immutable text with the integrity metadata retained in project history. */
export function recordText(text: string, mediaType: string): RecordedText {
  return { text, sha256: sourceSha256(text), mediaType };
}

/** Read the current authored DSL contract fingerprint and best-effort Git provenance. */
export async function readDslRevision(root = process.cwd()): Promise<DslRevision | undefined> {
  try {
    const contentSha256 = await fingerprintRepositoryFiles(root, dslContractInputPaths);
    const git = await readGitRevision(root);
    return { contentSha256, ...git };
  } catch (error) {
    console.error('Could not identify the Sverlin DSL revision.', error);
    return undefined;
  }
}

async function readGitRevision(root: string): Promise<Omit<DslRevision, 'contentSha256'>> {
  try {
    const [{ stdout: commit }, { stdout: status }] = await Promise.all([
      execFileAsync('git', ['rev-parse', '--verify', 'HEAD'], { cwd: root }),
      execFileAsync(
        'git',
        ['status', '--porcelain=v1', '--untracked-files=normal', '--', ...dslContractInputPaths],
        { cwd: root }
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
