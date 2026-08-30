/** Prepared compiler discovery and source-fingerprint validation. */

import { createHash, randomUUID } from 'node:crypto';
import { access, mkdir, open, readFile, readdir, rename, rm, stat } from 'node:fs/promises';
import path from 'node:path';

export const repositoryRoot = process.cwd();
const preparedCompilerSchemaVersion = 1;

/** Return the OS-lock path shared by compiler invocation and preparation. */
export function compilerWorkspaceLockPath(root = repositoryRoot) {
  return path.join(root, '.cache', 'sverlin', 'compiler-workspace.lock');
}

// Keep this aligned with the compile-app component and its library inputs in
// compile/compile.cabal. Design documents, authoring examples, other executables,
// and vendored tests/samples do not affect the prepared compiler.
const fingerprintFiles = [
  'compile/compile.cabal',
  'compile/stack.yaml',
  'compile/stack.yaml.lock',
  'compile/app/Main.hs',
  'compile/vendor/MIP-0.2.0.1/MIP.cabal',
  'compile/vendor/MIP-0.2.0.1/Setup.hs'
];
const haskellSourceExtensions = new Set(['.hs', '.lhs', '.hs-boot', '.hsc', '.chs']);
const fingerprintDirectories = [
  { path: 'compile/app/Sverlin', extensions: haskellSourceExtensions },
  { path: 'compile/cbits', extensions: new Set(['.c', '.h']) },
  { path: 'compile/fonts', extensions: new Set(['.ttf']) },
  { path: 'compile/src', extensions: haskellSourceExtensions },
  { path: 'compile/vendor/MIP-0.2.0.1/src', extensions: haskellSourceExtensions }
];

/** Raised when no direct compiler binary matches the current checkout. */
export class CompilerNotReadyError extends Error {
  /** @param {string} message */
  constructor(message) {
    super(message);
    this.name = 'CompilerNotReadyError';
  }
}

/** Return the ignored descriptor path for a checkout. */
function preparedCompilerDescriptorPath(root = repositoryRoot) {
  const configured = process.env.SVERLIN_COMPILER_DIR?.trim();
  return configured
    ? path.join(path.resolve(configured), 'compiler.json')
    : path.join(root, '.cache', 'sverlin', 'compiler.json');
}

/**
 * Return the runtime environment required by the direct compiler executable.
 *
 * @param {{ ghcEnvironmentPath: string }} prepared
 * @param {string} [root]
 */
export function preparedCompilerEnvironment(prepared, root = repositoryRoot) {
  return {
    ...process.env,
    GHC_ENVIRONMENT: prepared.ghcEnvironmentPath,
    compile_datadir: path.join(root, 'compile'),
    MIP_datadir: path.join(root, 'compile', 'vendor', 'MIP-0.2.0.1')
  };
}

/** Hash every owned source, configuration, and bundled asset used by the compiler. */
export async function compilerSourceFingerprint(root = repositoryRoot) {
  const relativePaths = [...fingerprintFiles];
  for (const input of fingerprintDirectories) {
    relativePaths.push(...(await filesBelow(root, input.path, input.extensions)));
  }
  relativePaths.sort();

  const hash = createHash('sha256');
  for (const relativePath of relativePaths) {
    hash.update(relativePath);
    hash.update('\0');
    hash.update(await readFile(path.join(root, relativePath)));
    hash.update('\0');
  }
  return hash.digest('hex');
}

/**
 * Atomically record one successfully built compiler binary.
 *
 * @param {string} binaryPath
 * @param {string} sourceSha256
 * @param {string} ghcEnvironment
 * @param {string} [root]
 */
export async function writePreparedCompiler(
  binaryPath,
  sourceSha256,
  ghcEnvironment,
  root = repositoryRoot
) {
  if (!path.isAbsolute(binaryPath)) throw new Error('Prepared compiler path must be absolute.');
  await assertExecutable(binaryPath);
  assertSha256(sourceSha256);

  if (typeof ghcEnvironment !== 'string' || !ghcEnvironment.includes('package-id compile-')) {
    throw new Error('Prepared compiler GHC environment is invalid.');
  }
  const environmentPath = path.join(
    path.dirname(preparedCompilerDescriptorPath(root)),
    `ghc-${sourceSha256}.environment`
  );
  const descriptor = {
    schemaVersion: preparedCompilerSchemaVersion,
    sourceSha256,
    binaryPath,
    ghcEnvironmentPath: environmentPath,
    preparedAt: new Date().toISOString()
  };
  const destination = preparedCompilerDescriptorPath(root);
  await mkdir(path.dirname(destination), { recursive: true });
  await writeAtomicDurable(environmentPath, ghcEnvironment);
  await writeAtomicDurable(destination, `${JSON.stringify(descriptor, null, 2)}\n`);
  return descriptor;
}

/** Read and verify that the prepared binary exactly matches current inputs. */
export async function readPreparedCompiler(root = repositoryRoot) {
  let parsed;
  try {
    parsed = JSON.parse(await readFile(preparedCompilerDescriptorPath(root), 'utf8'));
  } catch (error) {
    throw new CompilerNotReadyError(
      `The compiler has not been prepared (${error instanceof Error ? error.message : String(error)}).`
    );
  }

  if (
    !parsed ||
    parsed.schemaVersion !== preparedCompilerSchemaVersion ||
    typeof parsed.binaryPath !== 'string' ||
    !path.isAbsolute(parsed.binaryPath) ||
    typeof parsed.ghcEnvironmentPath !== 'string' ||
    !path.isAbsolute(parsed.ghcEnvironmentPath) ||
    typeof parsed.sourceSha256 !== 'string' ||
    typeof parsed.preparedAt !== 'string' ||
    Number.isNaN(Date.parse(parsed.preparedAt))
  ) {
    throw new CompilerNotReadyError('The prepared compiler descriptor is invalid.');
  }

  try {
    assertSha256(parsed.sourceSha256);
    await assertExecutable(parsed.binaryPath);
    if (!(await stat(parsed.ghcEnvironmentPath)).isFile()) {
      throw new Error('Prepared compiler GHC environment is not a file.');
    }
    await assertLocalCompilerPackage(await readFile(parsed.ghcEnvironmentPath, 'utf8'));
  } catch (error) {
    throw new CompilerNotReadyError(error instanceof Error ? error.message : String(error));
  }

  if ((await compilerSourceFingerprint(root)) !== parsed.sourceSha256) {
    throw new CompilerNotReadyError('Compiler inputs changed after the binary was prepared.');
  }
  return parsed;
}

/**
 * Verify that Stack's mutable local package registration still matches the environment.
 * @param {string} ghcEnvironment
 */
async function assertLocalCompilerPackage(ghcEnvironment) {
  const lines = ghcEnvironment.split(/\r?\n/);
  const packageDatabases = lines
    .filter((line) => line.startsWith('package-db '))
    .map((line) => line.slice('package-db '.length).trim());
  const compilerUnit = lines
    .find((line) => line.startsWith('package-id compile-'))
    ?.slice('package-id '.length)
    .trim();
  if (!compilerUnit || packageDatabases.length === 0) {
    throw new Error('Prepared compiler GHC environment is invalid.');
  }

  for (const database of packageDatabases) {
    try {
      if ((await stat(path.join(database, `${compilerUnit}.conf`))).isFile()) return;
    } catch (error) {
      if (!(error instanceof Error && 'code' in error && error.code === 'ENOENT')) throw error;
    }
  }
  throw new Error('Prepared compiler package registration changed; prepare the compiler again.');
}

/** @param {string} destination @param {string} contents */
async function writeAtomicDurable(destination, contents) {
  const temporary = `${destination}.${randomUUID()}.tmp`;
  const handle = await open(temporary, 'wx');
  try {
    await handle.writeFile(contents, 'utf8');
    await handle.sync();
  } finally {
    await handle.close();
  }
  try {
    await rename(temporary, destination);
    await syncDirectory(path.dirname(destination));
  } finally {
    await rm(temporary, { force: true });
  }
}

/** @param {string} directory */
async function syncDirectory(directory) {
  if (process.platform === 'win32') return;
  const handle = await open(directory, 'r');
  try {
    await handle.sync();
  } catch (error) {
    if (!isUnsupportedDirectorySyncError(error)) throw error;
  } finally {
    await handle.close();
  }
}

/** @param {unknown} error */
export function isUnsupportedDirectorySyncError(error) {
  return (
    error instanceof Error &&
    'code' in error &&
    typeof error.code === 'string' &&
    ['EINVAL', 'ENOTSUP', 'EBADF'].includes(error.code)
  );
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
    const relativePath = path.join(relativeDirectory, entry.name);
    if (entry.isDirectory() && entry.name !== '.stack-work') {
      files.push(...(await filesBelow(root, relativePath, extensions)));
    } else if (entry.isFile() && extensions.has(path.extname(entry.name))) {
      files.push(relativePath);
    }
  }
  return files;
}

/** @param {string} binaryPath */
async function assertExecutable(binaryPath) {
  const details = await stat(binaryPath);
  if (!details.isFile()) throw new Error('Prepared compiler path is not a file.');
  await access(binaryPath, process.platform === 'win32' ? undefined : 1);
}

/** @param {string} value */
function assertSha256(value) {
  if (!/^[a-f0-9]{64}$/.test(value)) throw new Error('Invalid compiler input fingerprint.');
}
