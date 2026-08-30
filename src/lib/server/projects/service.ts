/**
 * Server-side project operations and the event-recorded compilation lifecycle.
 *
 * @packageDocumentation
 */

import { randomInt, randomUUID } from 'node:crypto';

import type {
  EventId,
  NewProjectEvent,
  ProjectEventOf,
  ProjectEventType
} from '$lib/shared/projects/events';
import type {
  ArtifactChange,
  ArtifactVersionOrigin,
  RecordedText,
  RenderPurpose
} from '$lib/shared/projects/events/values';
import type {
  ProjectCommandResult,
  ProjectDocument,
  ProjectResource
} from '$lib/shared/projects/model';
import { defaultProjectCreation, type ProjectCreation } from '$lib/shared/projects/creation';
import { projectHead, projectSnapshotAt } from '$lib/shared/projects/projection';
import { visualizationService, type VisualizationGenerationResult } from '$lib/server/compiler';

import { runProjectCommand } from './command-lock';
import { currentProjectOperationSignal } from './operation-context';
import { readDslRevision, recordText } from './fingerprints';
import { projectRepository, type ProjectResourceBlob } from './repository';
import { resolveProjectTemplate } from './starter-catalog';

const minSeed = 1;
const maxSeedExclusive = 2147483647;
const entryArtifactId = 'dsl-main';

type RecordedCompilationBase = {
  document: ProjectDocument;
  source: RecordedText;
  sourceLabel: string;
  seed: number;
  operationId: string;
};

/** Compilation result together with the immutable event and blobs recorded for it. */
export type RecordedCompilation = RecordedCompilationBase &
  (
    | {
        result: Extract<VisualizationGenerationResult, { ok: true }>;
        compileEvent: NewProjectEvent<'compilation.succeeded'>;
        render: RecordedText;
      }
    | {
        result: Extract<VisualizationGenerationResult, { ok: false }>;
        compileEvent: NewProjectEvent<'compilation.failed'>;
      }
  );

/** Options for creating one project from an immutable template. */
type CreateProjectOptions = {
  creation?: ProjectCreation;
  title?: string;
  ownerUserId?: string;
  projectId?: string;
  operationId?: string;
};

/** Replaceable project-side effects used by database-free domain tests. */
export type ProjectServiceDependencies = {
  repository: typeof projectRepository;
  compiler: typeof visualizationService;
  readDslRevision: typeof readDslRevision;
};

export const defaultProjectServiceDependencies: ProjectServiceDependencies = {
  repository: projectRepository,
  compiler: visualizationService,
  readDslRevision
};

/** Create a project from its validated template and render the initial visualization. */
export async function createProject(
  options: CreateProjectOptions = {},
  dependencies: ProjectServiceDependencies = defaultProjectServiceDependencies
): Promise<ProjectDocument> {
  const { document, operationId } = await createProjectSkeleton(options, dependencies);
  const seed = randomInt(minSeed, maxSeedExclusive);
  return renderDocument(document, seed, 'initial', operationId, dependencies);
}

/** Persist the cheap event-sourced project skeleton before asynchronous compilation. */
export async function createProjectSkeleton(
  options: CreateProjectOptions = {},
  dependencies: ProjectServiceDependencies = defaultProjectServiceDependencies
): Promise<{ document: ProjectDocument; operationId: string }> {
  const creation = options.creation ?? defaultProjectCreation;
  const template = resolveProjectTemplate(creation);
  const title = options.title?.trim() || template.title;
  const projectId = options.projectId ?? randomUUID();
  const operationId = options.operationId ?? randomUUID();
  const root: ProjectEventOf<'project.created'> = {
    id: 1,
    type: 'project.created',
    actor: { kind: 'user' },
    operationId,
    createdAt: new Date().toISOString(),
    payload: { title, entryArtifactId, creation }
  };
  let document = await dependencies.repository.create(
    { schemaVersion: 1, projectId, events: [root] },
    options.ownerUserId
  );
  const content = recordText(template.source, 'text/x-sverlin');
  document = await appendProjectEvents(
    document,
    [
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
    ],
    [],
    dependencies
  );
  return { document, operationId };
}

/** Compile the initial artifact for a previously persisted skeleton. */
export async function renderInitialProject(
  options: {
    projectId: string;
    expectedHead: EventId;
    seed: number;
    operationId: string;
  },
  dependencies: ProjectServiceDependencies = defaultProjectServiceDependencies
): Promise<ProjectCommandResult> {
  return runProjectCommand(options.projectId, async () => {
    const before = await checkedDocument(options.projectId, options.expectedHead, dependencies);
    const document = await renderDocument(
      before,
      options.seed,
      'initial',
      options.operationId,
      dependencies
    );
    return commandResult(before, document);
  });
}

/** Load the complete project document and project selector metadata. */
export async function loadProjectResource(
  projectId: string,
  ownerUserId?: string,
  dependencies: ProjectServiceDependencies = defaultProjectServiceDependencies
): Promise<ProjectResource> {
  const document = await dependencies.repository.load(projectId);
  return { document, projects: await dependencies.repository.list(ownerUserId) };
}

/** Compile the current artifact with a new seed and record the resulting events. */
export function renderProject(
  options: {
    projectId: string;
    expectedHead: EventId;
    seed: number;
    operationId: string;
  },
  dependencies: ProjectServiceDependencies = defaultProjectServiceDependencies
): Promise<ProjectCommandResult> {
  return runProjectCommand(options.projectId, async () => {
    const before = await checkedDocument(options.projectId, options.expectedHead, dependencies);
    const document = await renderDocument(
      before,
      options.seed,
      'seed-change',
      options.operationId,
      dependencies
    );
    return commandResult(before, document);
  });
}

/** Append a user-authored project title change. */
export function renameProject(
  options: {
    projectId: string;
    expectedHead: EventId;
    title: string;
    operationId: string;
  },
  dependencies: ProjectServiceDependencies = defaultProjectServiceDependencies
): Promise<ProjectCommandResult> {
  return runProjectCommand(options.projectId, async () => {
    const before = await checkedDocument(options.projectId, options.expectedHead, dependencies);
    const snapshot = projectSnapshotAt(before);
    const title = options.title.trim();
    if (!title) throw new Error('Project title cannot be empty.');
    if (title === snapshot.title) return commandResult(before, before);
    const document = await appendProjectEvents(
      before,
      [
        draftEvent({
          type: 'project.renamed',
          actor: { kind: 'user' },
          operationId: options.operationId,
          payload: { previousTitle: snapshot.title, title }
        })
      ],
      [],
      dependencies
    );
    return commandResult(before, document);
  });
}

/** Save a manual artifact version and compile it into a new visualization. */
export function updateProjectArtifact(
  options: {
    projectId: string;
    expectedHead: EventId;
    artifactId: string;
    source: string;
    seed: number;
    operationId: string;
  },
  dependencies: ProjectServiceDependencies = defaultProjectServiceDependencies
): Promise<ProjectCommandResult> {
  return runProjectCommand(options.projectId, async () => {
    const before = await checkedDocument(options.projectId, options.expectedHead, dependencies);
    const current = projectSnapshotAt(before).artifacts[options.artifactId];
    if (!current) throw new Error(`Unknown artifact ${options.artifactId}.`);
    const content = recordText(options.source, 'text/x-sverlin');
    let document = await appendProjectEvents(
      before,
      [
        artifactVersionEvent({
          operationId: options.operationId,
          origin: { kind: 'manual-edit' },
          changes: [{ operation: 'upsert', artifact: { ...current, content } }]
        })
      ],
      [],
      dependencies
    );
    document = await renderDocument(
      document,
      options.seed,
      'manual-edit',
      options.operationId,
      dependencies
    );
    return commandResult(before, document);
  });
}

/** Copy historical artifacts forward and compile them as a new project state. */
export function restoreProjectArtifacts(
  options: {
    projectId: string;
    expectedHead: EventId;
    from: EventId;
    seed: number;
    operationId: string;
  },
  dependencies: ProjectServiceDependencies = defaultProjectServiceDependencies
): Promise<ProjectCommandResult> {
  return runProjectCommand(options.projectId, async () => {
    const before = await checkedDocument(options.projectId, options.expectedHead, dependencies);
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
    let document = await appendProjectEvents(
      before,
      [
        artifactVersionEvent({
          operationId: options.operationId,
          origin: { kind: 'restore', restoredFrom: options.from },
          changes
        })
      ],
      [],
      dependencies
    );
    document = await renderDocument(
      document,
      options.seed,
      'restore',
      options.operationId,
      dependencies
    );
    return commandResult(before, document);
  });
}

/** Atomically append events to the supplied document's current head. */
export async function appendProjectEvents(
  document: ProjectDocument,
  events: NewProjectEvent[],
  resources: readonly ProjectResourceBlob[] = [],
  dependencies: ProjectServiceDependencies = defaultProjectServiceDependencies
): Promise<ProjectDocument> {
  return (
    await dependencies.repository.append(
      document.projectId,
      projectHead(document).id,
      events,
      resources
    )
  ).document;
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
  operationId: string,
  dependencies: ProjectServiceDependencies
) {
  const snapshot = projectSnapshotAt(document);
  const artifact = snapshot.artifacts[snapshot.entryArtifactId];
  if (!artifact) throw new Error('The project has no entry artifact.');
  const recorded = await compileProjectSource(
    {
      document,
      sourceContent: artifact.content.text,
      source: artifact.content,
      sourceLabel: artifact.path,
      seed,
      purpose,
      input: 'committed-artifact',
      operationId
    },
    dependencies
  );
  return recorded.result.ok ? activateCompiledRender(recorded, dependencies) : recorded.document;
}

/** Compile source and immutably record the request, diagnostics, and output blobs. */
export async function compileProjectSource(
  options: {
    document: ProjectDocument;
    sourceContent: string;
    source: RecordedText;
    sourceLabel: string;
    seed: number;
    purpose: RenderPurpose;
    input: 'committed-artifact' | 'assistant-candidate';
    operationId: string;
    attempt?: 1 | 2;
  },
  dependencies: ProjectServiceDependencies = defaultProjectServiceDependencies
): Promise<RecordedCompilation> {
  const dslRevision = await dependencies.readDslRevision();
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
  const document = await appendProjectEvents(options.document, [request], [], dependencies);
  const result = await dependencies.compiler.generate({
    source: { name: logicalSourceName(options.sourceLabel), content: options.sourceContent },
    seed: options.seed,
    signal: currentProjectOperationSignal()
  });
  return recordCompileResult({ ...options, document, result }, dependencies);
}

async function recordCompileResult(
  options: {
    document: ProjectDocument;
    result: VisualizationGenerationResult;
    source: RecordedText;
    sourceLabel: string;
    seed: number;
    operationId: string;
  },
  dependencies: ProjectServiceDependencies
): Promise<RecordedCompilation> {
  const stdout = recordText(options.result.execution.stdout, 'text/plain');
  const stderr = recordText(options.result.execution.stderr, 'text/plain');

  if (!options.result.ok) {
    const compileEvent = draftEvent<'compilation.failed'>({
      type: 'compilation.failed',
      actor: { kind: 'system' },
      operationId: options.operationId,
      payload: {
        durationMs: options.result.execution.durationMs,
        exitCode: options.result.execution.exitCode,
        failureKind: options.result.failureKind ?? 'pipeline',
        diagnostics: options.result.diagnostics,
        stdout,
        stderr,
        timedOut: options.result.execution.timedOut,
        repairEligible:
          options.result.failureKind === 'source' || options.result.failureKind === 'pipeline',
        ...(options.result.error ? { error: options.result.error } : {})
      }
    });
    return {
      document: await appendProjectEvents(options.document, [compileEvent], [], dependencies),
      result: options.result,
      compileEvent,
      source: options.source,
      sourceLabel: options.sourceLabel,
      seed: options.seed,
      operationId: options.operationId
    };
  }

  const render = recordText(JSON.stringify(options.result.visualization), 'application/json');
  const resources = options.result.resources.map(({ bytes: _bytes, ...resource }) => resource);
  const compileEvent = draftEvent<'compilation.succeeded'>({
    type: 'compilation.succeeded',
    actor: { kind: 'system' },
    operationId: options.operationId,
    payload: {
      durationMs: options.result.execution.durationMs,
      stdout,
      stderr,
      render,
      resources,
      provenance: options.result.provenance,
      targetDiagnostics: options.result.targetDiagnostics
    }
  });
  return {
    document: await appendProjectEvents(
      options.document,
      [compileEvent],
      options.result.resources,
      dependencies
    ),
    result: options.result,
    compileEvent,
    render,
    source: options.source,
    sourceLabel: options.sourceLabel,
    seed: options.seed,
    operationId: options.operationId
  };
}

/** Promote a successful recorded compilation to the project's active visualization. */
export async function activateCompiledRender(
  recorded: RecordedCompilation,
  dependencies: ProjectServiceDependencies = defaultProjectServiceDependencies
): Promise<ProjectDocument> {
  if (!('render' in recorded)) return recorded.document;
  const document = await appendProjectEvents(
    recorded.document,
    [
      draftEvent({
        type: 'visualization.rendered',
        actor: { kind: 'system' },
        operationId: recorded.operationId,
        payload: {
          seed: recorded.seed,
          source: recorded.source,
          render: recorded.render,
          resources: recorded.result.ok
            ? recorded.result.resources.map(({ bytes: _bytes, ...resource }) => resource)
            : [],
          ...(recorded.result.ok
            ? {
                provenance: recorded.result.provenance,
                targetDiagnostics: recorded.result.targetDiagnostics
              }
            : {})
        }
      })
    ],
    [],
    dependencies
  );
  return document;
}

function logicalSourceName(sourceLabel: string): string {
  const name = sourceLabel.split(/[\\/]/).at(-1) || 'Main.sverlin';
  return name.endsWith('.sverlin') ? name : `${name}.sverlin`;
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

async function checkedDocument(
  projectId: string,
  expectedHead: EventId,
  dependencies: ProjectServiceDependencies
) {
  const document = await dependencies.repository.load(projectId);
  if (projectHead(document).id !== expectedHead) {
    const error = new Error('The project changed before this operation completed.');
    error.name = 'ProjectConflictError';
    throw error;
  }
  return document;
}
