/** Renderer-neutral preference and manual HTML presentation commands. */

import { randomUUID } from 'node:crypto';

import type { EventId, NewProjectEvent } from '$lib/shared/projects/events';
import type { VisualSelection } from '$lib/shared/projects/events/values';
import type { ProjectCommandResult, ProjectDocument } from '$lib/shared/projects/model';
import type { HtmlFramesManifest } from '$lib/shared/presentations';
import { presentationStepLabels } from '$lib/shared/presentations';
import { projectHead, projectSnapshotAt } from '$lib/shared/projects/projection';
import { validateHtmlFramesManifest } from '$lib/server/visualization-modes/html-safety';
import { stepSignature } from '$lib/server/visualization-modes';

import { runProjectCommand } from './command-lock';
import { recordText } from './fingerprints';
import { projectRepository } from './repository';
import { resolveProjectVisualSelection } from './visual-selection';
import {
  appendProjectEvents,
  defaultProjectServiceDependencies,
  draftEvent,
  type ProjectServiceDependencies
} from './service';

/** Replaceable persistence boundary for presentation-command unit tests. */
export type PresentationCommandDependencies = {
  repository: typeof projectRepository;
  projectService: ProjectServiceDependencies;
};

const defaultDependencies: PresentationCommandDependencies = {
  repository: projectRepository,
  projectService: defaultProjectServiceDependencies
};

/** Record a preference between any two compatible retained Sverlin presentations. */
export function recordProjectPreference(
  options: {
    projectId: string;
    expectedHead: EventId;
    presentations: [string, string];
    preferred: string;
    step: number;
    visualSelections: VisualSelection[];
    operationId: string;
  },
  dependencies: PresentationCommandDependencies = defaultDependencies
): Promise<ProjectCommandResult> {
  return runProjectCommand(options.projectId, async () => {
    const before = await checkedDocument(options.projectId, options.expectedHead, dependencies);
    const document = await appendProjectPreference(before, options, dependencies.projectService);
    return { document, appendedEvents: document.events.slice(before.events.length) };
  });
}

/** Validate and append a preference inside a larger already-locked project command. */
export async function appendProjectPreference(
  document: ProjectDocument,
  options: {
    presentations: [string, string];
    preferred: string;
    step: number;
    visualSelections: VisualSelection[];
    operationId: string;
  },
  dependencies: ProjectServiceDependencies
): Promise<ProjectDocument> {
  const supplied = [...new Set(options.presentations)];
  if (supplied.length !== 2 || !supplied.includes(options.preferred)) {
    throw new Error('The preference must identify two distinct presentations and one winner.');
  }
  const presented = supplied.map((id) =>
    document.events.find(
      (event) =>
        event.type === 'visualization.presented' && event.payload.presentation.presentationId === id
    )
  );
  if (presented.some((event) => event?.type !== 'visualization.presented')) {
    throw new Error('The preference references an unknown presentation.');
  }
  const [left, right] = presented;
  if (left?.type !== 'visualization.presented' || right?.type !== 'visualization.presented') {
    throw new Error('The preference references an unknown presentation.');
  }
  const leftPresentation = left.payload.presentation;
  const rightPresentation = right.payload.presentation;
  if (
    leftPresentation.format !== 'sverlin-ir-v1' ||
    rightPresentation.format !== 'sverlin-ir-v1' ||
    leftPresentation.source.sha256 !== rightPresentation.source.sha256 ||
    leftPresentation.stepSignature !== rightPresentation.stepSignature
  ) {
    throw new Error('Only compatible versions of the same visualization can be compared.');
  }
  if (
    options.step >= presentationStepLabels(leftPresentation).length ||
    options.step >= presentationStepLabels(rightPresentation).length
  ) {
    throw new Error('The preference references an unknown presentation step.');
  }
  const allowedEvents = new Set([left.id, right.id]);
  const visualSelections = options.visualSelections.map((selection) => {
    const resolved = resolveProjectVisualSelection(document, selection).selection;
    if (!allowedEvents.has(resolved.presentationEvent) || resolved.step !== options.step) {
      throw new Error('Preference focus must belong to the compared presentations and step.');
    }
    return resolved;
  });
  if (
    visualSelections.length > 2 ||
    new Set(visualSelections.map(({ presentationEvent }) => presentationEvent)).size !==
      visualSelections.length
  ) {
    throw new Error('A preference may focus each compared presentation at most once.');
  }
  const displaySetId =
    left.payload.displaySetId === right.payload.displaySetId
      ? left.payload.displaySetId
      : undefined;
  return appendProjectEvents(
    document,
    [
      draftEvent({
        type: 'visualization.preference-recorded',
        actor: { kind: 'user' },
        operationId: options.operationId,
        payload: {
          ...(displaySetId ? { displaySetId } : {}),
          presentations: options.presentations,
          preferred: options.preferred,
          step: options.step,
          visualSelections
        }
      })
    ],
    [],
    dependencies
  );
}

/** Save and immediately present one complete editable HTML manifest. */
export function saveHtmlProjectArtifact(
  options: {
    projectId: string;
    expectedHead: EventId;
    artifactId: string;
    manifest: HtmlFramesManifest;
    operationId: string;
  },
  dependencies: PresentationCommandDependencies = defaultDependencies
): Promise<ProjectCommandResult> {
  return runProjectCommand(options.projectId, async () => {
    const before = await checkedDocument(options.projectId, options.expectedHead, dependencies);
    const snapshot = projectSnapshotAt(before);
    if (snapshot.renderer !== 'html') throw new Error('This project does not use HTML frames.');
    const current = snapshot.artifacts[options.artifactId];
    if (!current) throw new Error(`Unknown artifact ${options.artifactId}.`);
    const { authored, rendered } = validateHtmlFramesManifest(options.manifest);
    const authoredText = recordText(
      JSON.stringify(authored),
      'application/vnd.sverlin.html-frames+json'
    );
    const renderedText = recordText(
      JSON.stringify(rendered),
      'application/vnd.sverlin.html-frames+json'
    );
    const events: NewProjectEvent[] = [
      draftEvent({
        type: 'artifact.version-created',
        actor: { kind: 'user' },
        operationId: options.operationId,
        payload: {
          origin: { kind: 'manual-edit' },
          changes: [
            {
              operation: 'upsert',
              artifact: { ...current, language: 'json', content: authoredText }
            }
          ]
        }
      }),
      draftEvent({
        type: 'visualization.presented',
        actor: { kind: 'user' },
        operationId: options.operationId,
        payload: {
          displaySetId: randomUUID(),
          slot: 0,
          presentation: {
            presentationId: randomUUID(),
            format: 'html-frames-v1',
            stepSignature: stepSignature(rendered.frames.map(({ label }) => label)),
            authored: authoredText,
            rendered: renderedText
          }
        }
      })
    ];
    const document = await appendProjectEvents(before, events, [], dependencies.projectService);
    return { document, appendedEvents: document.events.slice(before.events.length) };
  });
}

async function checkedDocument(
  projectId: string,
  expectedHead: EventId,
  dependencies: PresentationCommandDependencies
) {
  const document = await dependencies.repository.load(projectId);
  if (projectHead(document).id !== expectedHead) {
    const error = new Error('The project changed before this operation completed.');
    error.name = 'ProjectConflictError';
    throw error;
  }
  return document;
}
