/**
 * Server-side project operations and the event-recorded compilation lifecycle.
 *
 * @packageDocumentation
 */

import { randomInt, randomUUID } from 'node:crypto';

import bundledInitialSource from '../../../../examples/Minimal.sverlin?raw';

import type {
  EventId,
  NewProjectEvent,
  ProjectEventOf,
  ProjectEventType
} from '$lib/projects/events';
import type {
  ArtifactChange,
  ArtifactVersionOrigin,
  BlobRef,
  RenderPurpose
} from '$lib/projects/events/values';
import type { ProjectCommandResult, ProjectDocument, ProjectView } from '$lib/projects/model';
import { projectHead, projectSnapshotAt } from '$lib/projects/projection';
import { compileSource, type CompileVisualizationResult } from '$lib/server/compile-visualization';
import { decodeVisualization } from '$lib/visualization/types';

import { runProjectCommand } from './command-lock';
import { readDslRevision } from './fingerprints';
import { projectRepository } from './repository';

const minSeed = 1;
const maxSeedExclusive = 2147483647;
const entryArtifactId = 'dsl-main';

type RecordedCompilationBase = {
  document: ProjectDocument;
  source: BlobRef;
  seed: number;
  operationId: string;
};

/** Compilation result together with the immutable event and blobs recorded for it. */
export type RecordedCompilation = RecordedCompilationBase &
  (
    | {
        result: Extract<CompileVisualizationResult, { ok: true }>;
        compileEvent: NewProjectEvent<'compilation.succeeded'>;
        render: BlobRef;
      }
    | {
        result: Extract<CompileVisualizationResult, { ok: false }>;
        compileEvent: NewProjectEvent<'compilation.failed'>;
      }
  );

/** Create a project from the bundled minimal source and render its initial visualization. */
export async function createProject(title = 'Untitled visualization'): Promise<ProjectDocument> {
  const projectId = randomUUID();
  const operationId = randomUUID();
  const root: ProjectEventOf<'project.created'> = {
    id: 1,
    type: 'project.created',
    actor: { kind: 'user' },
    operationId,
    createdAt: new Date().toISOString(),
    payload: { title, entryArtifactId }
  };
  let document = await projectRepository.create({ schemaVersion: 1, projectId, events: [root] });
  const content = await projectRepository.putBlob(
    projectId,
    bundledInitialSource,
    'text/x-sverlin'
  );
  document = await appendProjectEvents(document, [
    draftEvent({
      type: 'artifact.version-created',
      actor: { kind: 'system' },
      operationId,
      payload: {
        origin: { kind: 'initial' },
        changes: [
          {
            operation: 'upsert',
            artifact: {
              artifactId: entryArtifactId,
              path: 'Main.sverlin',
              language: 'sverlin',
              content
            }
          }
        ]
      }
    })
  ]);
  return renderDocument(document, randomInt(minSeed, maxSeedExclusive), 'initial', operationId);
}

/** Load a project, reconstruct the requested state, and hydrate its blobs for the UI. */
export async function loadProjectView(projectId: string, at?: EventId): Promise<ProjectView> {
  const document = await projectRepository.load(projectId);
  const snapshot = projectSnapshotAt(document, at);
  const artifacts = Object.fromEntries(
    await Promise.all(
      Object.entries(snapshot.artifacts).map(async ([artifactId, artifact]) => [
        artifactId,
        {
          ...artifact,
          source: await projectRepository.readTextBlob(projectId, artifact.content)
        }
      ])
    )
  );
  const visualization = snapshot.activeRender
    ? decodeVisualization(
        await projectRepository.readTextBlob(projectId, snapshot.activeRender.payload.render)
      )
    : undefined;

  return {
    document,
    snapshot: { ...snapshot, artifacts },
    ...(visualization ? { visualization } : {}),
    projects: await projectRepository.list()
  };
}

/** Compile the current artifact with a new seed and record the resulting events. */
export function renderProject(options: {
  projectId: string;
  expectedHead: EventId;
  seed: number;
  operationId: string;
}): Promise<ProjectCommandResult> {
  return runProjectCommand(options.projectId, async () => {
    const before = await checkedDocument(options.projectId, options.expectedHead);
    const document = await renderDocument(before, options.seed, 'seed-change', options.operationId);
    return commandResult(before, document);
  });
}

/** Append a user-authored project title change. */
export function renameProject(options: {
  projectId: string;
  expectedHead: EventId;
  title: string;
  operationId: string;
}): Promise<ProjectCommandResult> {
  return runProjectCommand(options.projectId, async () => {
    const before = await checkedDocument(options.projectId, options.expectedHead);
    const snapshot = projectSnapshotAt(before);
    const title = options.title.trim();
    if (!title) throw new Error('Project title cannot be empty.');
    if (title === snapshot.title) return commandResult(before, before);
    const document = await appendProjectEvents(before, [
      draftEvent({
        type: 'project.renamed',
        actor: { kind: 'user' },
        operationId: options.operationId,
        payload: { previousTitle: snapshot.title, title }
      })
    ]);
    return commandResult(before, document);
  });
}

/** Save a manual artifact version and compile it into a new visualization. */
export function updateProjectArtifact(options: {
  projectId: string;
  expectedHead: EventId;
  artifactId: string;
  source: string;
  seed: number;
  operationId: string;
}): Promise<ProjectCommandResult> {
  return runProjectCommand(options.projectId, async () => {
    const before = await checkedDocument(options.projectId, options.expectedHead);
    const current = projectSnapshotAt(before).artifacts[options.artifactId];
    if (!current) throw new Error(`Unknown artifact ${options.artifactId}.`);
    const content = await projectRepository.putBlob(
      options.projectId,
      options.source,
      'text/x-sverlin'
    );
    let document = await appendProjectEvents(before, [
      artifactVersionEvent({
        operationId: options.operationId,
        origin: { kind: 'manual-edit' },
        changes: [{ operation: 'upsert', artifact: { ...current, content } }]
      })
    ]);
    document = await renderDocument(document, options.seed, 'manual-edit', options.operationId);
    return commandResult(before, document);
  });
}

/** Copy historical artifacts forward and compile them as a new project state. */
export function restoreProjectArtifacts(options: {
  projectId: string;
  expectedHead: EventId;
  from: EventId;
  seed: number;
  operationId: string;
}): Promise<ProjectCommandResult> {
  return runProjectCommand(options.projectId, async () => {
    const before = await checkedDocument(options.projectId, options.expectedHead);
    const current = projectSnapshotAt(before);
    const historical = projectSnapshotAt(before, options.from);
    const changes: ArtifactChange[] = [
      ...Object.values(historical.artifacts).map(
        (artifact): ArtifactChange => ({ operation: 'upsert', artifact })
      ),
      ...Object.keys(current.artifacts)
        .filter((artifactId) => !(artifactId in historical.artifacts))
        .map((artifactId): ArtifactChange => ({ operation: 'delete', artifactId }))
    ];
    let document = await appendProjectEvents(before, [
      artifactVersionEvent({
        operationId: options.operationId,
        origin: { kind: 'restore', restoredFrom: options.from },
        changes
      })
    ]);
    document = await renderDocument(document, options.seed, 'restore', options.operationId);
    return commandResult(before, document);
  });
}

/** Atomically append events to the supplied document's current head. */
export async function appendProjectEvents(
  document: ProjectDocument,
  events: NewProjectEvent[]
): Promise<ProjectDocument> {
  return (await projectRepository.append(document.projectId, projectHead(document).id, events))
    .document;
}

/** Add a creation timestamp to a typed event before repository insertion. */
export function draftEvent<Type extends ProjectEventType>(
  event: Omit<NewProjectEvent<Type>, 'createdAt'>
): NewProjectEvent<Type> {
  return { ...event, createdAt: new Date().toISOString() } as NewProjectEvent<Type>;
}

async function renderDocument(
  document: ProjectDocument,
  seed: number,
  purpose: RenderPurpose,
  operationId: string
) {
  const snapshot = projectSnapshotAt(document);
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
    operationId
  });
  return recorded.result.ok ? activateCompiledRender(recorded) : recorded.document;
}

/** Compile source and immutably record the request, diagnostics, and output blobs. */
export async function compileProjectSource(options: {
  document: ProjectDocument;
  sourceContent: string;
  source: BlobRef;
  sourceLabel: string;
  seed: number;
  purpose: RenderPurpose;
  input: 'committed-artifact' | 'assistant-candidate';
  operationId: string;
  attempt?: 1 | 2;
}): Promise<RecordedCompilation> {
  const dslRevision = await readDslRevision();
  const request = draftEvent<'compilation.requested'>({
    type: 'compilation.requested',
    actor: { kind: 'system' },
    operationId: options.operationId,
    payload: {
      purpose: options.purpose,
      input: options.input,
      source: options.source,
      sourceLabel: options.sourceLabel,
      seed: options.seed,
      ...(options.attempt ? { attempt: options.attempt } : {}),
      ...(dslRevision ? { dslRevision } : {})
    }
  });
  const document = await appendProjectEvents(options.document, [request]);
  const result = await compileSource({
    sourceContent: options.sourceContent,
    sourceLabel: options.sourceLabel,
    seed: options.seed,
    owner: 'project'
  });
  return recordCompileResult({ ...options, document, result });
}

async function recordCompileResult(options: {
  document: ProjectDocument;
  result: CompileVisualizationResult;
  source: BlobRef;
  seed: number;
  operationId: string;
}): Promise<RecordedCompilation> {
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
    const compileEvent = draftEvent<'compilation.failed'>({
      type: 'compilation.failed',
      actor: { kind: 'system' },
      operationId: options.operationId,
      payload: {
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
    return {
      document: await appendProjectEvents(options.document, [compileEvent]),
      result: options.result,
      compileEvent,
      source: options.source,
      seed: options.seed,
      operationId: options.operationId
    };
  }

  const render = await projectRepository.putBlob(
    projectId,
    JSON.stringify(options.result.visualization),
    'application/json'
  );
  const compileEvent = draftEvent<'compilation.succeeded'>({
    type: 'compilation.succeeded',
    actor: { kind: 'system' },
    operationId: options.operationId,
    payload: { durationMs: options.result.debug.durationMs, stdout, stderr, render }
  });
  return {
    document: await appendProjectEvents(options.document, [compileEvent]),
    result: options.result,
    compileEvent,
    render,
    source: options.source,
    seed: options.seed,
    operationId: options.operationId
  };
}

/** Promote a successful recorded compilation to the project's active visualization. */
export async function activateCompiledRender(
  recorded: RecordedCompilation
): Promise<ProjectDocument> {
  if (!('render' in recorded)) return recorded.document;
  return appendProjectEvents(recorded.document, [
    draftEvent({
      type: 'visualization.rendered',
      actor: { kind: 'system' },
      operationId: recorded.operationId,
      payload: { seed: recorded.seed, source: recorded.source, render: recorded.render }
    })
  ]);
}

function artifactVersionEvent(options: {
  operationId: string;
  origin: ArtifactVersionOrigin;
  changes: ArtifactChange[];
}) {
  return draftEvent({
    type: 'artifact.version-created',
    actor:
      options.origin.kind === 'assistant-edit'
        ? { kind: 'assistant', botId: 'ai-assistant' }
        : { kind: 'user' },
    operationId: options.operationId,
    payload: { origin: options.origin, changes: options.changes }
  });
}

function commandResult(before: ProjectDocument, document: ProjectDocument): ProjectCommandResult {
  return { document, appendedEvents: document.events.slice(before.events.length) };
}

async function checkedDocument(projectId: string, expectedHead: EventId) {
  const document = await projectRepository.load(projectId);
  if (projectHead(document).id !== expectedHead) {
    const error = new Error('The project changed before this operation completed.');
    error.name = 'ProjectConflictError';
    throw error;
  }
  return document;
}
