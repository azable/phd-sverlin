import { lstat, mkdir, readlink, rename, rm, symlink } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const repositoryRoot = fileURLToPath(new URL('..', import.meta.url));
const staleStorageRoot = path.join(repositoryRoot, '.sverlin-stale-storage');

const links = [
  ['node_modules', '/opt/sverlin-dev/node_modules'],
  ['compile/.stack-work', '/opt/sverlin-dev/stack-work'],
  ['compile/vendor/MIP-0.2.0.1/.stack-work', '/opt/sverlin-dev/mip-stack-work']
];

async function currentLinkTarget(linkPath) {
  try {
    const metadata = await lstat(linkPath);
    return metadata.isSymbolicLink() ? await readlink(linkPath) : null;
  } catch (error) {
    if (error?.code === 'ENOENT') return undefined;
    throw error;
  }
}

for (const [relativePath, volumePath] of links) {
  const linkPath = path.join(repositoryRoot, relativePath);
  const existingTarget = await currentLinkTarget(linkPath);

  await mkdir(volumePath, { recursive: true });

  if (existingTarget === volumePath) {
    console.log(`${relativePath} already uses Docker-managed storage.`);
    continue;
  }

  if (existingTarget !== undefined) {
    try {
      await rm(linkPath, { recursive: true, force: true });
    } catch (error) {
      const stalePath = path.join(
        staleStorageRoot,
        `${relativePath.replaceAll('/', '-')}-${Date.now()}`
      );

      await mkdir(staleStorageRoot, { recursive: true });
      await rename(linkPath, stalePath);
      console.warn(
        `Could not remove ${relativePath} (${error.code ?? 'unknown error'}); preserved it at ${path.relative(repositoryRoot, stalePath)}.`
      );
    }
  }

  await mkdir(path.dirname(linkPath), { recursive: true });
  await symlink(volumePath, linkPath, 'dir');
  console.log(`Linked ${relativePath} to ${volumePath}.`);
}
