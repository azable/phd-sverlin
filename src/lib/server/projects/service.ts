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
import { markdownMessage } from '$lib/shared/projects/events/message-content';
import {
  defaultProjectCreation,
  projectCreationRenderer,
  type ProjectCreation
} from '$lib/shared/projects/creation';
import type { HtmlFramesManifest, SverlinPresentation } from '$lib/shared/presentations';
import { projectHead, projectSnapshotAt } from '$lib/shared/projects/projection';
import { presentationBufferState } from '$lib/shared/projects/presentation-buffer';
import { visualizationService, type VisualizationGenerationResult } from '$lib/server/compiler';
import { assistantIntroduction } from '$lib/server/chat-bots/registry';

import { runProjectCommand } from './command-lock';
import { currentProjectOperationSignal } from './operation-context';
import { readDslRevision, recordText } from './fingerprints';
import { projectRepository, type ProjectResourceBlob } from './repository';
import { resolveProjectTemplate } from './starter-catalog';
import { createHtmlPresentation, stepSignature } from '$lib/server/visualization-modes';

const minSeed = 1;
const maxSeedExclusive = 2147483647;
const entryArtifactId = 'dsl-main';
const initialHtmlManifest: HtmlFramesManifest = {
  format: 'sverlin-html-frames',
  version: 1,
  frames: [
    {
      label: 'Start',
      html: '<main><h1>Start your visualization</h1><p>Describe what you would like to create in the timeline.</p></main>'
    }
  ]
};

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
  presentationCount?: 1 | 2;
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

/** Create a project, leaving blank conversational templates unrendered until first use. */
export async function createProject(
  options: CreateProjectOptions = {},
  dependencies: ProjectServiceDependencies = defaultProjectServiceDependencies
): Promise<ProjectDocument> {
  const { document, operationId } = await createProjectSkeleton(options, dependencies);
  if (projectSnapshotAt(document).creation.templateId === 'blank') return document;
  return renderDocument(
    document,
    freshPresentationSeeds(options.presentationCount ?? 1),
    'initial',
    operationId,
    dependencies
  );
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
  const renderer = projectCreationRenderer(creation);
  const html = renderer === 'html';
  const content = recordText(
    html ? JSON.stringify(initialHtmlManifest) : template.source,
    html ? 'application/vnd.sverlin.html-frames+json' : 'text/x-sverlin'
  );
  const artifact: ProjectEventOf<'artifact.version-created'> = {
    id: 2,
    ...draftEvent<'artifact.version-created'>({
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
              path: html ? 'Visualization.html.json' : 'Main.sverlin',
              language: html ? 'json' : 'sverlin',
              content
            }
          }
        ]
      }
    })
  };
  const introduction = assistantIntroduction(renderer);
  const initialEvents: ProjectDocument['events'] = [root, artifact];
  if (creation.templateId === 'blank') {
    initialEvents.push({
      id: 3,
      ...draftEvent<'assistant.responded'>({
        type: 'assistant.responded',
        actor: { kind: 'assistant', botId: introduction.botId },
        operationId,
        payload: { content: markdownMessage(introduction.text) }
      })
    });
  }
  const document = await dependencies.repository.create(
    { schemaVersion: 2, projectId, events: initialEvents },
    options.ownerUserId
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
      [options.seed],
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
      [options.seed],
      'seed-change',
      options.operationId,
      dependencies
    );
    return commandResult(before, document);
  });
}

/** Generate one or two fresh presentations from the currently accepted artifact. */
export function renderProjectPresentations(
  options: {
    projectId: string;
    expectedHead: EventId;
    presentationCount: 1 | 2;
    operationId: string;
  },
  dependencies: ProjectServiceDependencies = defaultProjectServiceDependencies
): Promise<ProjectCommandResult> {
  return runProjectCommand(options.projectId, async () => {
    const before = await checkedDocument(options.projectId, options.expectedHead, dependencies);
    const document = await renderDocument(
      before,
      freshPresentationSeeds(options.presentationCount),
      'seed-change',
      options.operationId,
      dependencies
    );
    return commandResult(before, document);
  });
}

/** Fill the current committed source's configured buffer with fresh seeded presentations. */
export function replenishProjectPresentations(
  options: {
    projectId: string;
    expectedHead: EventId;
    target: number;
    operationId: string;
  },
  dependencies: ProjectServiceDependencies = defaultProjectServiceDependencies
): Promise<ProjectCommandResult> {
  return runProjectCommand(options.projectId, async () => {
    const before = await checkedDocument(options.projectId, options.expectedHead, dependencies);
    let document = before;
    for (;;) {
      const state = presentationBufferState(document, options.target);
      if (state.deficit === 0) break;
      const count = Math.min(2, state.deficit) as 1 | 2;
      const usedSeeds = document.events.flatMap((event) =>
        event.type === 'visualization.presented' &&
        event.payload.presentation.format === 'sverlin-ir-v1' &&
        event.payload.presentation.source.sha256 === state.sourceSha256
          ? [event.payload.presentation.seed]
          : []
      );
      const next = await renderDocument(
        document,
        freshPresentationSeeds(count, usedSeeds),
        'seed-change',
        options.operationId,
        dependencies
      );
      const nextState = presentationBufferState(next, options.target);
      document = next;
      if (nextState.available.length <= state.available.length) break;
    }
    return commandResult(before, document);
  });
}

/** Consume the currently visible buffered candidates only after an explicit participant action. */
export function advanceProjectPresentations(
  options: {
    projectId: string;
    expectedHead: EventId;
    presentations: string[];
    operationId: string;
  },
  dependencies: ProjectServiceDependencies = defaultProjectServiceDependencies
): Promise<ProjectCommandResult> {
  return runProjectCommand(options.projectId, async () => {
    const before = await checkedDocument(options.projectId, options.expectedHead, dependencies);
    const available = new Set(
      presentationBufferState(before, 0).available.map(({ presentationId }) => presentationId)
    );
    if (
      options.presentations.length === 0 ||
      options.presentations.length > 2 ||
      options.presentations.some((id) => !available.has(id))
    ) {
      throw new Error('Only currently available presentations can be advanced.');
    }
    const document = await appendProjectEvents(
      before,
      [
        draftEvent({
          type: 'visualization.candidates-advanced',
          actor: { kind: 'user' },
          operationId: options.operationId,
          payload: { presentations: options.presentations, reason: 'next' }
        })
      ],
      [],
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
    presentationCount: 1 | 2;
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
      freshPresentationSeeds(options.presentationCount),
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
      [options.seed],
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
  seeds: readonly number[],
  purpose: RenderPurpose,
  operationId: string,
  dependencies: ProjectServiceDependencies
) {
  const snapshot = projectSnapshotAt(document);
  const artifact = snapshot.artifacts[snapshot.entryArtifactId];
  if (!artifact) throw new Error('The project has no entry artifact.');
  if (snapshot.renderer === 'html') {
    const presentation = createHtmlPresentation(
      JSON.parse(artifact.content.text) as HtmlFramesManifest
    );
    return appendProjectEvents(
      document,
      [
        draftEvent({
          type: 'visualization.presented',
          actor: { kind: 'system' },
          operationId,
          payload: {
            displaySetId: randomUUID(),
            slot: 0,
            presentation
          }
        })
      ],
      [],
      dependencies
    );
  }
  if (seeds.length === 0) throw new Error('At least one seed is required.');
  const recorded = await compileProjectSourceBatch(
    {
      document,
      sourceContent: artifact.content.text,
      source: artifact.content,
      sourceLabel: artifact.path,
      seeds,
      purpose,
      input: 'committed-artifact',
      operationId
    },
    dependencies
  );
  return recorded.compilations.every(({ result }) => result.ok)
    ? activateCompiledPresentations(recorded, dependencies)
    : recorded.document;
}

export type RecordedCompilationBatch = {
  document: ProjectDocument;
  compilations: RecordedCompilation[];
};

/** Compile one source for several seeds through the public batch service and record each result. */
export async function compileProjectSourceBatch(
  options: {
    document: ProjectDocument;
    sourceContent: string;
    source: RecordedText;
    sourceLabel: string;
    seeds: readonly number[];
    purpose: RenderPurpose;
    input: 'committed-artifact' | 'assistant-candidate';
    operationId: string;
    attempt?: 1 | 2;
  },
  dependencies: ProjectServiceDependencies = defaultProjectServiceDependencies
): Promise<RecordedCompilationBatch> {
  if (options.seeds.length === 0) throw new Error('At least one seed is required.');
  const dslRevision = await dependencies.readDslRevision();
  const requests = options.seeds.map((seed) =>
    draftEvent<'compilation.requested'>({
      type: 'compilation.requested',
      actor: { kind: 'system' },
      operationId: options.operationId,
      payload: {
        purpose: options.purpose,
        input: options.input,
        source: options.source,
        sourceLabel: options.sourceLabel,
        seed,
        ...(options.attempt ? { attempt: options.attempt } : {}),
        ...(dslRevision ? { dslRevision } : {})
      }
    })
  );
  let document = await appendProjectEvents(options.document, requests, [], dependencies);
  const results = await dependencies.compiler.generateBatch({
    source: { name: logicalSourceName(options.sourceLabel), content: options.sourceContent },
    seeds: options.seeds,
    signal: currentProjectOperationSignal()
  });
  if (results.length !== options.seeds.length) {
    throw new Error('The visualization service returned an incomplete batch.');
  }
  if (results.some((result, index) => result.seed !== options.seeds[index])) {
    throw new Error('The visualization service returned an incorrectly correlated batch.');
  }
  const compilations: RecordedCompilation[] = [];
  for (const [index, result] of results.entries()) {
    const recorded = await recordCompileResult(
      {
        document,
        result,
        source: options.source,
        sourceLabel: options.sourceLabel,
        seed: options.seeds[index],
        operationId: options.operationId
      },
      dependencies
    );
    document = recorded.document;
    compilations.push(recorded);
  }
  return { document, compilations };
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

/** Promote a complete successful batch to one synchronized active display set. */
export async function activateCompiledPresentations(
  recorded: RecordedCompilationBatch,
  dependencies: ProjectServiceDependencies = defaultProjectServiceDependencies,
  actor: NewProjectEvent<'visualization.presented'>['actor'] = { kind: 'system' }
): Promise<ProjectDocument> {
  if (recorded.compilations.length === 0 || recorded.compilations.some((item) => !item.result.ok)) {
    throw new Error('Only a complete successful compilation batch can be presented.');
  }
  if (recorded.compilations.length > 2) {
    throw new Error('A display set supports at most two presentations.');
  }
  const presentations = recorded.compilations.map((item): SverlinPresentation => {
    if (!item.result.ok || !('render' in item)) {
      throw new Error('A failed compilation cannot become a presentation.');
    }
    return {
      presentationId: randomUUID(),
      format: 'sverlin-ir-v1',
      stepSignature: stepSignature(item.result.visualization.steps.map(({ label }) => label)),
      seed: item.seed,
      source: item.source,
      render: item.render,
      resources: item.result.resources.map(({ bytes: _bytes, ...resource }) => resource),
      provenance: item.result.provenance,
      targetDiagnostics: item.result.targetDiagnostics
    };
  });
  if (new Set(presentations.map(({ stepSignature: signature }) => signature)).size !== 1) {
    throw new Error('Synchronized presentations must expose the same ordered steps.');
  }
  const displaySetId = randomUUID();
  const operationId = recorded.compilations[0].operationId;
  return appendProjectEvents(
    recorded.document,
    presentations.map((presentation, slot) =>
      draftEvent({
        type: 'visualization.presented',
        actor,
        operationId,
        payload: { displaySetId, slot: slot as 0 | 1, presentation }
      })
    ),
    [],
    dependencies
  );
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
        ? { kind: 'assistant', botId: 'sverlin-assistant' }
        : { kind: 'user' },
    operationId: options.operationId,
    payload: { origin: options.origin, changes: options.changes }
  });
}

/** Choose distinct positive seeds for one server-owned presentation generation. */
export function freshPresentationSeeds(count: 1 | 2, excluded: readonly number[] = []): number[] {
  const blocked = new Set(excluded);
  const seeds: number[] = [];
  while (seeds.length < count) {
    const seed = randomInt(minSeed, maxSeedExclusive);
    if (!blocked.has(seed) && !seeds.includes(seed)) seeds.push(seed);
  }
  return seeds;
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
