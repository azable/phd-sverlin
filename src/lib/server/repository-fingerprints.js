/** Canonical repository inputs for compiler and authored-DSL fingerprints. */

import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';

/**
 * Files that define the authored Sverlin language contract.
 *
 * Prompt guidance is deliberately excluded. The generated API index captures
 * the GHC-checked public surface, while Source.hs owns the body-only source
 * format supplied to the compiler.
 */
export const dslContractInputPaths = Object.freeze([
  'compile/app/Sverlin/Source.hs',
  'compile/src/Sverlin.hs',
  'compile/src/Sverlin/Linear.hs',
  'src/lib/server/chat-bots/sverlin-assistant/dsl-api-index.md'
]);

const compilerFingerprintFiles = [
  'compile/compile.cabal',
  'compile/stack.yaml',
  'compile/stack.yaml.lock',
  'compile/app/Main.hs',
  'compile/vendor/MIP-0.2.0.1/MIP.cabal',
  'compile/vendor/MIP-0.2.0.1/Setup.hs'
];
const haskellSourceExtensions = new Set(['.hs', '.lhs', '.hs-boot', '.hsc', '.chs']);
const compilerFingerprintDirectories = [
  { path: 'compile/app/Sverlin', extensions: haskellSourceExtensions },
  { path: 'compile/cbits', extensions: new Set(['.c', '.h']) },
  { path: 'compile/fonts', extensions: new Set(['.ttf']) },
  { path: 'compile/src', extensions: haskellSourceExtensions },
  { path: 'compile/vendor/MIP-0.2.0.1/src', extensions: haskellSourceExtensions }
];

/**
 * List every owned source, configuration file, and asset used by compile-app.
 *
 * @param {string} root
 * @returns {Promise<string[]>}
 */
export async function compilerInputPaths(root) {
  const relativePaths = [...compilerFingerprintFiles];
  for (const input of compilerFingerprintDirectories) {
    relativePaths.push(...(await filesBelow(root, input.path, input.extensions)));
  }
  return relativePaths.sort();
}

/**
 * Hash repository-relative paths and their exact bytes in stable path order.
 *
 * @param {string} root
 * @param {ReadonlyArray<string>} relativePaths
 * @returns {Promise<string>}
 */
export async function fingerprintRepositoryFiles(root, relativePaths) {
  const sortedPaths = [...relativePaths].sort();
  if (new Set(sortedPaths).size !== sortedPaths.length) {
    throw new Error('Fingerprint input paths must be unique.');
  }

  const hash = createHash('sha256');
  for (const relativePath of sortedPaths) {
    hash.update(relativePath);
    hash.update('\0');
    hash.update(await readFile(path.join(root, relativePath)));
    hash.update('\0');
  }
  return hash.digest('hex');
}

/**
 * @param {string} root
 * @param {string} relativeDirectory
 * @param {ReadonlySet<string>} extensions
 * @returns {Promise<string[]>}
 */
async function filesBelow(root, relativeDirectory, extensions) {
  const directory = path.join(root, relativeDirectory);
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const relativePath = path.posix.join(relativeDirectory, entry.name);
    if (entry.isDirectory() && entry.name !== '.stack-work') {
      files.push(...(await filesBelow(root, relativePath, extensions)));
    } else if (entry.isFile() && extensions.has(path.extname(entry.name))) {
      files.push(relativePath);
    }
  }
  return files;
}
