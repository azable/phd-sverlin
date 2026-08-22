import { randomInt, randomUUID } from 'node:crypto';

import bundledInitialSource from '../../../../examples/Minimal.sverlin?raw';

import { projectAt, projectHead } from '$lib/projects/project';
import type {
  ArtifactChange,
  ArtifactVersionOrigin,
  BlobRef,
  NewProjectEvent,
  ProjectCommandResult,
  ProjectDocument,
  ProjectEvent,
  ProjectEventId,
  ProjectPageState,
  RenderPurpose
} from '$lib/projects/types';
import { compileSource, type CompileVisualizationResult } from '$lib/server/compile-visualization';
import type { CompiledVisualization } from '$lib/visualization/types';

import { runProjectCommand } from './command-lock';
import { projectRepository } from './repository';

const minSeed = 1;
const maxSeedExclusive = 2147483647;
const entryArtifactId = 'dsl-main';

export async function createProject(title = 'Untitled visualization') {
  const projectId = randomUUID();
  const correlationId = randomUUID();
  const root = rootEvent({
    type: 'project.created',
    actor: { kind: 'user' },
    correlationId,
    payload: { title, entryArtifactId }
  });
  let document = await projectRepository.create({ schemaVersion: 1, projectId, events: [root] });
  const source = await projectRepository.putBlob(projectId, bundledInitialSource, 'text/x-sverlin');
  const artifactEvent = draftEvent({
    type: 'artifact.version-created',
    actor: { kind: 'system' },
    correlationId,
    causationEventId: root.eventId,
    payload: {
      origin: { kind: 'initial' },
      changes: [
        {
          operation: 'upsert',
          artifact: {
            artifactId: entryArtifactId,
            path: 'Main.sverlin',
            language: 'sverlin',
            content: source,
            contentSha256: source.sha256
          }
        }
      ]
    }
  });
  document = (await projectRepository.append(projectId, root.eventId, [artifactEvent])).document;
  document = await renderDocument(
    document,
    randomInt(minSeed, maxSeedExclusive),
    'initial',
    correlationId
  );
  return loadProjectPage(projectId, projectHead(document).eventId);
}

export async function loadProjectPage(
  projectId: string,
  cursorEventId?: ProjectEventId
): Promise<ProjectPageState> {
  const document = await projectRepository.load(projectId);
  const cursor = cursorEventId ?? projectHead(document).eventId;
  const snapshot = projectAt(document, cursor);
  const artifacts = Object.fromEntries(
    await Promise.all(
      Object.entries(snapshot.artifacts).map(async ([artifactId, artifact]) => [
        artifactId,
        {
          ...artifact,
          content: await projectRepository.readTextBlob(projectId, artifact.content)
        }
      ])
    )
  );
  const trace = snapshot.activeRender
    ? await readTrace(projectId, snapshot.activeRender.payload.render)
    : undefined;

  return {
    document,
    cursorEventId: cursor,
    headEventId: projectHead(document).eventId,
    snapshot: { ...snapshot, artifacts },
    ...(trace ? { trace } : {})
  };
}

export async function renderProject(options: {
  projectId: string;
  expectedHeadEventId: string;
  seed: number;
  purpose?: RenderPurpose;
  correlationId?: string;
}): Promise<ProjectCommandResult> {
  return runProjectCommand(options.projectId, () => renderProjectUnlocked(options));
}

export async function renameProject(options: {
  projectId: string;
  expectedHeadEventId: string;
  title: string;
  correlationId?: string;
}) {
  return runProjectCommand(options.projectId, () => renameProjectUnlocked(options));
}

async function renameProjectUnlocked(options: {
  projectId: string;
  expectedHeadEventId: string;
  title: string;
  correlationId?: string;
}) {
  const before = await projectRepository.load(options.projectId);
  assertHead(before, options.expectedHeadEventId);
  const snapshot = projectAt(before);
  const title = options.title.trim();
  if (!title) throw new Error('Project title cannot be empty.');
  if (title === snapshot.title) return commandResult(before, before);
  const renamed = draftEvent<'project.renamed'>({
    type: 'project.renamed',
    actor: { kind: 'user' },
    correlationId: options.correlationId ?? randomUUID(),
    payload: { previousTitle: snapshot.title, title }
  });
  const document = await appendProjectEvents(before, [renamed]);
  return commandResult(before, document);
}

async function renderProjectUnlocked(options: {
  projectId: string;
  expectedHeadEventId: string;
  seed: number;
  purpose?: RenderPurpose;
  correlationId?: string;
}): Promise<ProjectCommandResult> {
  const before = await projectRepository.load(options.projectId);
  assertHead(before, options.expectedHeadEventId);
  const document = await renderDocument(
    before,
    options.seed,
    options.purpose ?? 'seed-change',
    options.correlationId ?? randomUUID()
  );
  return commandResult(before, document);
}

export async function updateProjectArtifact(options: {
  projectId: string;
  expectedHeadEventId: string;
  artifactId: string;
  content: string;
  seed: number;
  correlationId?: string;
}) {
  return runProjectCommand(options.projectId, () => updateProjectArtifactUnlocked(options));
}

async function updateProjectArtifactUnlocked(options: {
  projectId: string;
  expectedHeadEventId: string;
  artifactId: string;
  content: string;
  seed: number;
  correlationId?: string;
}) {
  const before = await projectRepository.load(options.projectId);
  assertHead(before, options.expectedHeadEventId);
  const snapshot = projectAt(before);
  const current = snapshot.artifacts[options.artifactId];
  if (!current) throw new Error(`Unknown artifact ${options.artifactId}.`);
  const content = await projectRepository.putBlob(
    options.projectId,
    options.content,
    'text/x-sverlin'
  );
  const correlationId = options.correlationId ?? randomUUID();
  const artifactEvent = artifactVersionEvent({
    correlationId,
    origin: { kind: 'manual-edit' },
    changes: [
      {
        operation: 'upsert',
        artifact: { ...current, content, contentSha256: content.sha256 }
      }
    ]
  });
  let document = (
    await projectRepository.append(options.projectId, projectHead(before).eventId, [artifactEvent])
  ).document;
  document = await renderDocument(document, options.seed, 'manual-edit', correlationId);
  return commandResult(before, document);
}

export async function restoreProjectArtifacts(options: {
  projectId: string;
  expectedHeadEventId: string;
  restoredFromEventId: string;
  seed: number;
  correlationId?: string;
}) {
  return runProjectCommand(options.projectId, () => restoreProjectArtifactsUnlocked(options));
}

async function restoreProjectArtifactsUnlocked(options: {
  projectId: string;
  expectedHeadEventId: string;
  restoredFromEventId: string;
  seed: number;
  correlationId?: string;
}) {
  const before = await projectRepository.load(options.projectId);
  assertHead(before, options.expectedHeadEventId);
  const current = projectAt(before);
  const historical = projectAt(before, options.restoredFromEventId);
  const changes: ArtifactChange[] = [
    ...Object.values(historical.artifacts).map(
      (artifact): ArtifactChange => ({ operation: 'upsert', artifact })
    ),
    ...Object.keys(current.artifacts)
      .filter((artifactId) => !(artifactId in historical.artifacts))
      .map((artifactId): ArtifactChange => ({ operation: 'delete', artifactId }))
  ];
  const correlationId = options.correlationId ?? randomUUID();
  const artifactEvent = artifactVersionEvent({
    correlationId,
    origin: { kind: 'restore', restoredFromEventId: options.restoredFromEventId },
    changes
  });
  let document = (
    await projectRepository.append(options.projectId, projectHead(before).eventId, [artifactEvent])
  ).document;
  document = await renderDocument(document, options.seed, 'restore', correlationId);
  return commandResult(before, document);
}

export async function appendProjectEvents(
  document: ProjectDocument,
  events: NewProjectEvent[]
): Promise<ProjectDocument> {
  return (await projectRepository.append(document.projectId, projectHead(document).eventId, events))
    .document;
}

export function draftEvent<Type extends ProjectEvent['type']>(
  event: Omit<NewProjectEvent<Type>, 'eventId' | 'createdAt'>
): NewProjectEvent<Type> {
  return {
    ...event,
    eventId: randomUUID(),
    createdAt: new Date().toISOString()
  } as NewProjectEvent<Type>;
}

async function renderDocument(
  document: ProjectDocument,
  seed: number,
  purpose: RenderPurpose,
  correlationId: string
) {
  const snapshot = projectAt(document);
  const artifact = snapshot.artifacts[snapshot.entryArtifactId];
  if (!artifact) throw new Error('The project has no entry artifact.');
  const sourceContent = await projectRepository.readTextBlob(document.projectId, artifact.content);
  const recorded = await compileProjectSource({
    document,
    sourceContent,
    source: artifact.content,
    sourceLabel: artifact.path,
    seed,
    purpose,
    input: 'committed-artifact',
    correlationId
  });
  if (!recorded.result.ok) return recorded.document;
  return activateCompiledRender(recorded);
}

export async function compileProjectSource(options: {
  document: ProjectDocument;
  sourceContent: string;
  source: BlobRef;
  sourceLabel: string;
  seed: number;
  purpose: RenderPurpose;
  input: 'committed-artifact' | 'assistant-candidate';
  correlationId: string;
}) {
  const renderRequest = draftEvent<'visualization.render-requested'>({
    type: 'visualization.render-requested',
    actor: { kind: 'system' },
    correlationId: options.correlationId,
    payload: {
      purpose: options.purpose,
      seed: options.seed,
      source: options.source,
      sourceSha256: options.source.sha256,
      sourceLabel: options.sourceLabel,
      input: options.input
    }
  });
  let document = await appendProjectEvents(options.document, [renderRequest]);
  const compileRequest = draftEvent<'compilation.requested'>({
    type: 'compilation.requested',
    actor: { kind: 'system' },
    correlationId: options.correlationId,
    causationEventId: renderRequest.eventId,
    payload: {
      renderRequestEventId: renderRequest.eventId,
      source: options.source,
      sourceSha256: options.source.sha256,
      sourceLabel: options.sourceLabel,
      seed: options.seed
    }
  });
  document = await appendProjectEvents(document, [compileRequest]);
  const result = await compileSource({
    sourceContent: options.sourceContent,
    sourceLabel: options.sourceLabel,
    seed: options.seed,
    owner: 'project'
  });
  return recordCompileResult({
    document,
    result,
    source: options.source,
    seed: options.seed,
    renderRequest,
    compileRequest,
    correlationId: options.correlationId
  });
}

async function recordCompileResult(options: {
  document: ProjectDocument;
  result: CompileVisualizationResult;
  source: BlobRef;
  seed: number;
  renderRequest: NewProjectEvent<'visualization.render-requested'>;
  compileRequest: NewProjectEvent<'compilation.requested'>;
  correlationId: string;
}) {
  const projectId = options.document.projectId;
  const stdout = await projectRepository.putBlob(
    projectId,
    options.result.debug.stdout,
    'text/plain'
  );
  const stderr = await projectRepository.putBlob(
    projectId,
    options.result.debug.stderr,
    'text/plain'
  );

  if (!options.result.ok) {
    const failed = draftEvent({
      type: 'compilation.failed',
      actor: { kind: 'system' },
      correlationId: options.correlationId,
      causationEventId: options.compileRequest.eventId,
      payload: {
        requestEventId: options.compileRequest.eventId,
        durationMs: options.result.debug.durationMs,
        exitCode: options.result.debug.exitCode,
        failureKind: options.result.failureKind ?? 'pipeline',
        diagnostics: options.result.diagnostics,
        stdout,
        stderr,
        timedOut: options.result.debug.timedOut ?? false,
        repairEligible:
          options.result.failureKind === 'source' || options.result.failureKind === 'pipeline',
        ...(options.result.error ? { error: options.result.error } : {})
      }
    });
    const document = await appendProjectEvents(options.document, [failed]);
    return {
      document,
      result: options.result,
      renderRequest: options.renderRequest,
      compileEvent: failed
    };
  }

  const renderJson = JSON.stringify(options.result.trace);
  const render = await projectRepository.putBlob(projectId, renderJson, 'application/json');
  const succeeded = draftEvent({
    type: 'compilation.succeeded',
    actor: { kind: 'system' },
    correlationId: options.correlationId,
    causationEventId: options.compileRequest.eventId,
    payload: {
      requestEventId: options.compileRequest.eventId,
      durationMs: options.result.debug.durationMs,
      exitCode: options.result.debug.exitCode ?? 0,
      diagnostics: [],
      stdout,
      stderr,
      render,
      renderSha256: render.sha256,
      cacheHit: false
    }
  });
  const document = await appendProjectEvents(options.document, [succeeded]);
  return {
    document,
    result: options.result,
    renderRequest: options.renderRequest,
    compileEvent: succeeded,
    render
  };
}

export async function activateCompiledRender(
  recorded: Awaited<ReturnType<typeof compileProjectSource>>
) {
  if (!recorded.result.ok || !recorded.render) return recorded.document;
  const latestSnapshot = projectAt(recorded.document);
  const artifactVersionEventId =
    latestSnapshot.artifactVersionEventIds[latestSnapshot.entryArtifactId];
  if (!artifactVersionEventId) throw new Error('The rendered artifact has no version event.');
  const rendered = draftEvent<'visualization.rendered'>({
    type: 'visualization.rendered',
    actor: { kind: 'system' },
    correlationId: recorded.renderRequest.correlationId,
    causationEventId: recorded.compileEvent.eventId,
    payload: {
      renderRequestEventId: recorded.renderRequest.eventId,
      compilationEventId: recorded.compileEvent.eventId,
      artifactVersionEventId,
      artifactVersions: latestSnapshot.artifactVersionEventIds,
      seed: recorded.renderRequest.payload.seed,
      render: recorded.render,
      renderSha256: recorded.render.sha256,
      sourceSha256: recorded.renderRequest.payload.sourceSha256,
      cacheHit: false
    }
  });
  return appendProjectEvents(recorded.document, [rendered]);
}

function artifactVersionEvent(options: {
  correlationId: string;
  origin: ArtifactVersionOrigin;
  changes: ArtifactChange[];
}) {
  return draftEvent({
    type: 'artifact.version-created',
    actor:
      options.origin.kind === 'assistant-edit'
        ? { kind: 'assistant', botId: 'ai-assistant' }
        : { kind: 'user' },
    correlationId: options.correlationId,
    payload: { origin: options.origin, changes: options.changes }
  });
}

function rootEvent(
  event: Omit<
    Extract<ProjectEvent, { type: 'project.created' }>,
    'eventId' | 'sequence' | 'parentEventId' | 'createdAt'
  >
): Extract<ProjectEvent, { type: 'project.created' }> {
  return {
    ...event,
    eventId: randomUUID(),
    sequence: 0,
    parentEventId: null,
    createdAt: new Date().toISOString()
  };
}

function commandResult(before: ProjectDocument, document: ProjectDocument): ProjectCommandResult {
  return { document, appendedEvents: document.events.slice(before.events.length) };
}

function assertHead(document: ProjectDocument, expectedHeadEventId: string) {
  if (projectHead(document).eventId !== expectedHeadEventId) {
    const error = new Error('The project changed before this operation completed.');
    error.name = 'ProjectConflictError';
    throw error;
  }
}

async function readTrace(projectId: string, ref: BlobRef) {
  return JSON.parse(await projectRepository.readTextBlob(projectId, ref)) as CompiledVisualization;
}
