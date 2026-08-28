#!/usr/bin/env node

import { spawn } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { link, mkdir, mkdtemp, open, readFile, readdir, rm, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

const repositoryRoot = path.resolve(process.env.SVERLIN_REPOSITORY_ROOT?.trim() || process.cwd());
const stateRoot = process.env.SVERLIN_STATE_DIR?.trim();
const projectRoot = path.resolve(
  process.env.SVERLIN_PROJECT_DIR?.trim() ||
    (stateRoot ? path.join(stateRoot, 'projects') : path.join(repositoryRoot, 'data', 'projects'))
);
const output = path.resolve(readOutputPath());
const staging = await mkdtemp(path.join(tmpdir(), 'sverlin-export-'));
const temporaryArchive = `${output}.${randomUUID()}.tmp`;

try {
  const projectsDestination = path.join(staging, 'projects');
  await mkdir(projectsDestination, { recursive: true });
  const entries = await readdir(projectRoot, { withFileTypes: true });
  const manifestProjects = [];

  for (const entry of entries.toSorted((left, right) => left.name.localeCompare(right.name))) {
    if (!entry.isDirectory() || !isProjectId(entry.name)) continue;
    const project = await snapshotProject(entry.name, projectsDestination);
    manifestProjects.push(project);
  }

  const manifest = {
    schemaVersion: 1,
    createdAt: new Date().toISOString(),
    projectCount: manifestProjects.length,
    projects: manifestProjects
  };
  await writeDurable(
    path.join(staging, 'manifest.json'),
    Buffer.from(`${JSON.stringify(manifest, null, 2)}\n`)
  );

  await mkdir(path.dirname(output), { recursive: true });
  await run('tar', ['-czf', temporaryArchive, '-C', staging, '.']);
  const archive = await open(temporaryArchive, 'r');
  try {
    await archive.sync();
  } finally {
    await archive.close();
  }
  await link(temporaryArchive, output);
  await syncDirectory(path.dirname(output));
  console.log(
    JSON.stringify({ output, projectCount: manifestProjects.length, source: projectRoot }, null, 2)
  );
} finally {
  await Promise.all([
    rm(staging, { recursive: true, force: true }),
    rm(temporaryArchive, { force: true })
  ]);
}

async function snapshotProject(projectId, projectsDestination) {
  const sourceDirectory = path.join(projectRoot, projectId);
  const sourceDocument = path.join(sourceDirectory, 'project.json');
  await assertBoundedFile(sourceDocument, 64 * 1024 * 1024, `Project ${projectId}`);
  const documentBytes = await readFile(sourceDocument);
  if (documentBytes.byteLength > 64 * 1024 * 1024) {
    throw new Error(`Project ${projectId} exceeds the 64 MiB document limit.`);
  }
  const document = JSON.parse(documentBytes.toString('utf8'));
  if (
    document?.schemaVersion !== 1 ||
    document.projectId !== projectId ||
    !Array.isArray(document.events)
  ) {
    throw new Error(`Project ${projectId} is not a valid version-one project document.`);
  }

  const destination = path.join(projectsDestination, projectId);
  await mkdir(destination, { recursive: false });
  await writeDurable(path.join(destination, 'project.json'), documentBytes);
  const resources = collectResources(document.events);
  const manifestResources = [];
  if (resources.size > 0) await mkdir(path.join(destination, 'resources'));

  for (const [resourceId, expected] of [...resources].sort(([left], [right]) =>
    left.localeCompare(right)
  )) {
    if (expected.byteLength > 16 * 1024 * 1024) {
      throw new Error(`Project ${projectId} resource ${resourceId} exceeds the 16 MiB limit.`);
    }
    const source = path.join(sourceDirectory, 'resources', resourceId);
    await assertBoundedFile(
      source,
      16 * 1024 * 1024,
      `Project ${projectId} resource ${resourceId}`
    );
    const bytes = await readFile(source);
    const digest = createHash('sha256').update(bytes).digest('hex');
    if (digest !== expected.sha256 || bytes.byteLength !== expected.byteLength) {
      throw new Error(`Project ${projectId} resource ${resourceId} failed integrity validation.`);
    }
    await writeDurable(path.join(destination, 'resources', resourceId), bytes);
    manifestResources.push({ id: resourceId, sha256: digest, byteLength: bytes.byteLength });
  }

  return {
    projectId,
    documentSha256: createHash('sha256').update(documentBytes).digest('hex'),
    documentByteLength: documentBytes.byteLength,
    resources: manifestResources
  };
}

async function assertBoundedFile(destination, maximum, label) {
  const details = await stat(destination);
  if (!details.isFile()) throw new Error(`${label} is not a regular file.`);
  if (details.size > maximum) throw new Error(`${label} exceeds the ${maximum} byte limit.`);
}

function collectResources(events) {
  const resources = new Map();
  for (const event of events) {
    const listed = event?.payload?.resources;
    if (!Array.isArray(listed)) continue;
    for (const resource of listed) {
      if (
        !resource ||
        typeof resource.id !== 'string' ||
        !/^sha256-[a-f0-9]{64}$/.test(resource.id) ||
        typeof resource.sha256 !== 'string' ||
        resource.id !== `sha256-${resource.sha256}` ||
        !Number.isSafeInteger(resource.byteLength) ||
        resource.byteLength < 0
      ) {
        throw new Error('A project contains an invalid resource descriptor.');
      }
      const existing = resources.get(resource.id);
      if (
        existing &&
        (existing.sha256 !== resource.sha256 || existing.byteLength !== resource.byteLength)
      ) {
        throw new Error(`Conflicting descriptors exist for ${resource.id}.`);
      }
      resources.set(resource.id, {
        sha256: resource.sha256,
        byteLength: resource.byteLength
      });
    }
  }
  return resources;
}

async function writeDurable(destination, bytes) {
  const handle = await open(destination, 'wx');
  try {
    await handle.writeFile(bytes);
    await handle.sync();
  } finally {
    await handle.close();
  }
}

async function syncDirectory(directory) {
  if (process.platform === 'win32') return;
  const handle = await open(directory, 'r');
  try {
    await handle.sync();
  } catch (error) {
    if (
      !(
        error instanceof Error &&
        'code' in error &&
        (error.code === 'EINVAL' || error.code === 'ENOTSUP' || error.code === 'EBADF')
      )
    ) {
      throw error;
    }
  } finally {
    await handle.close();
  }
}

function run(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: 'inherit' });
    child.on('error', reject);
    child.on('close', (exitCode) => {
      if (exitCode === 0) resolve();
      else reject(new Error(`${command} exited with code ${exitCode}.`));
    });
  });
}

function readOutputPath() {
  const args = process.argv.slice(2);
  const index = args.indexOf('--output');
  if (index >= 0) {
    const value = args[index + 1];
    if (!value || value.startsWith('--')) throw new Error('--output requires a file path.');
    return value;
  }
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  return path.join(repositoryRoot, 'data', 'project-archives', `sverlin-${timestamp}.tar.gz`);
}

function isProjectId(value) {
  return /^[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}$/.test(value);
}
