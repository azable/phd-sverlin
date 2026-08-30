/**
 * AI-owned projections from complete project history into bounded model context.
 *
 * The event document remains lossless. This module deliberately gives the model
 * a compact index, the current source, and expanded details only for the events
 * and rendered elements selected by the user.
 *
 * @packageDocumentation
 */

import {
  matchProjectEvent,
  type EventId,
  type ProjectEvent,
  type ProjectEventCases,
  type ProjectEventOf,
  type ProjectEventType
} from '$lib/shared/projects/events';
import type {
  CompilationProvenance,
  TargetDiagnostic,
  VisualSelection
} from '$lib/shared/projects/events/values';
import type { ProjectDocument, ProjectSnapshot } from '$lib/shared/projects/model';
import { projectHead, projectSnapshotAt } from '$lib/shared/projects/projection';
import {
  decodeVisualization,
  type RenderInstanceId,
  type VisualElement,
  type VisualizationFinding
} from '$lib/shared/visualization';
import type { ConversationMessage } from '$lib/server/chat-bots/types';

/** Compact, body-free entry that lets the AI identify any event in history. */
export type AiTimelineEntry = {
  id: EventId;
  type: ProjectEventType;
  actor: ProjectEvent['actor'];
  createdAt: string;
  operationId: string;
  summary: string;
};

/** Immutable source artifact exposed to the AI. */
export type AiArtifact = {
  artifactId: string;
  path: string;
  language: 'sverlin' | 'json';
  source: string;
  sha256: string;
};

/** Source state at one event position. */
export type AiWorkspace = {
  entryArtifactId: string;
  artifacts: AiArtifact[];
};

/** Compact identity of one activated visualization. */
export type AiRenderSummary = {
  id: EventId;
  seed: number;
  sourceSha256: string;
  renderSha256: string;
  provenance?: CompilationProvenance;
  targetDiagnostics?: TargetDiagnostic[];
};

/** Full details resolved for an event explicitly selected by the user. */
export type AiEventDetail = {
  event: ProjectEvent;
  workspace: AiWorkspace;
  activeRender?: AiRenderSummary;
};

/** One selected rendered element paired with its instance identity. */
export type AiSelectedElement = VisualElement & {
  instanceId: RenderInstanceId;
  findings: VisualizationFinding[];
};

/** Expanded visual details for a user-selected set of render instances. */
export type AiVisualSelection = VisualSelection & {
  stepLabel: string;
  renderSummary: AiRenderSummary;
  elements: AiSelectedElement[];
};

/** Explicit expansion request supplied by the feedback command. */
export type AiContextSelection = {
  eventIds: readonly EventId[];
  visualSelection?: VisualSelection;
};

/** Strongly typed, consumer-specific context supplied to the AI assistant. */
export type AiProjectContext = {
  projectId: string;
  title: string;
  headEventId: EventId;
  currentWorkspace: AiWorkspace;
  activeRender?: AiRenderSummary;
  activeVisualizationFindings: VisualizationFinding[];
  timeline: AiTimelineEntry[];
  selected: {
    events: AiEventDetail[];
    visualization?: AiVisualSelection;
  };
};

const timelineCases = {
  'project.created': (event) => `Created project “${event.payload.title}”.`,
  'project.renamed': (event) =>
    `Renamed project from “${event.payload.previousTitle}” to “${event.payload.title}”.`,
  'operation.accepted': (event) => `Accepted ${event.payload.kind} operation.`,
  'operation.completed': (event) => `Completed ${event.payload.kind} operation.`,
  'operation.failed': (event) =>
    `${event.payload.kind} operation failed (${event.payload.failureKind}): ${event.payload.message}`,
  'feedback.submitted': (event) =>
    `Submitted feedback${event.payload.focus.length ? ` focused on events ${event.payload.focus.join(', ')}` : ''}${event.payload.selection ? ' with a visual selection' : ''}.`,
  'ai.generation-requested': (event) =>
    `Requested ${event.payload.purpose} generation attempt ${event.payload.attempt} from ${event.payload.requestedModel}; prompt ${shortHash(event.payload.prompt.sha256)}.`,
  'ai.generation-succeeded': (event) =>
    `Generation attempt ${event.payload.attempt} succeeded with ${event.payload.model ?? event.payload.requestedModel}; response ${shortHash(event.payload.response.sha256)}.`,
  'ai.generation-failed': (event) =>
    `Generation attempt ${event.payload.attempt} failed (${event.payload.failureKind}): ${event.payload.message}`,
  'compilation.requested': (event) =>
    `Requested ${event.payload.purpose} compilation of ${event.payload.sourceLabel} at seed ${event.payload.seed}; source ${shortHash(event.payload.source.sha256)}.`,
  'compilation.succeeded': (event) =>
    `Compilation succeeded in ${event.payload.durationMs} ms; render ${shortHash(event.payload.render.sha256)}.`,
  'compilation.failed': (event) =>
    `Compilation failed (${event.payload.failureKind}) with ${event.payload.diagnostics.length} diagnostic(s).`,
  'artifact.version-created': (event) =>
    `Created ${event.payload.origin.kind} artifact version with ${event.payload.changes.length} change(s).`,
  'visualization.rendered': (event) =>
    `Activated seed ${event.payload.seed}; render ${shortHash(event.payload.render.sha256)}.`,
  'visualization.presented': (event) =>
    `Presented ${event.payload.presentation.format} visualization ${event.payload.presentation.presentationId} in display set ${event.payload.displaySetId}.`,
  'visualization.preference-recorded': (event) =>
    `Preferred presentation ${event.payload.preferred} over ${event.payload.presentations.find((id) => id !== event.payload.preferred) ?? 'the alternative'} at step ${event.payload.step}.`,
  'assistant.responded': () => 'Assistant responded to the user.',
  'system.notified': (event) => `System ${event.payload.severity}: ${event.payload.message}`
} satisfies ProjectEventCases<string>;

const conversationCases = {
  'project.created': () => [],
  'project.renamed': () => [],
  'operation.accepted': () => [],
  'operation.completed': () => [],
  'operation.failed': () => [],
  'feedback.submitted': (event) => [{ role: 'user', content: feedbackMessage(event) } as const],
  'ai.generation-requested': () => [],
  'ai.generation-succeeded': () => [],
  'ai.generation-failed': () => [],
  'compilation.requested': () => [],
  'compilation.succeeded': () => [],
  'compilation.failed': () => [],
  'artifact.version-created': () => [],
  'visualization.rendered': () => [],
  'visualization.presented': () => [],
  'visualization.preference-recorded': (event) => [
    {
      role: 'user',
      content: `I preferred presentation ${event.payload.preferred} over the alternative in display set ${event.payload.displaySetId} at step ${event.payload.step}.`
    } as const
  ],
  'assistant.responded': (event) => [{ role: 'assistant', content: event.payload.text } as const],
  'system.notified': () => []
} satisfies ProjectEventCases<ConversationMessage[]>;

/** Project one immutable event into the AI's compact, body-free timeline index. */
export function projectAiTimelineEntry(event: ProjectEvent): AiTimelineEntry {
  return {
    id: event.id,
    type: event.type,
    actor: event.actor,
    createdAt: event.createdAt,
    operationId: event.operationId,
    summary: matchProjectEvent(event, timelineCases)
  };
}

/** Project event history into conversational user and assistant messages. */
export function projectConversationMessages(
  events: readonly ProjectEvent[]
): ConversationMessage[] {
  return events.flatMap((event) =>
    matchProjectEvent<ConversationMessage[]>(event, conversationCases)
  );
}

/** Build the pure, explicitly bounded project context supplied to the AI assistant. */
export function projectAiContext(
  document: ProjectDocument,
  selection: AiContextSelection = { eventIds: [] }
): AiProjectContext {
  const snapshot = projectSnapshotAt(document);
  const visualization = selection.visualSelection
    ? resolveVisualSelection(document, selection.visualSelection)
    : undefined;

  return {
    projectId: document.projectId,
    title: snapshot.title,
    headEventId: projectHead(document).id,
    currentWorkspace: projectWorkspace(snapshot),
    ...(snapshot.activeRender ? { activeRender: renderSummary(snapshot.activeRender) } : {}),
    activeVisualizationFindings: snapshot.activeRender
      ? decodeVisualization(snapshot.activeRender.payload.render.text).findings
      : [],
    timeline: document.events.map(projectAiTimelineEntry),
    selected: {
      events: selection.eventIds.map((id) => eventDetail(document, id)),
      ...(visualization ? { visualization } : {})
    }
  };
}

function eventDetail(document: ProjectDocument, id: EventId): AiEventDetail {
  const event = document.events[id - 1];
  if (!event) throw new Error(`Unknown selected event ${id}.`);
  const snapshot = projectSnapshotAt(document, id);
  return {
    event,
    workspace: projectWorkspace(snapshot),
    ...(snapshot.activeRender ? { activeRender: renderSummary(snapshot.activeRender) } : {})
  };
}

function resolveVisualSelection(
  document: ProjectDocument,
  selection: VisualSelection
): AiVisualSelection | undefined {
  const render = document.events[selection.render - 1];
  if (render?.type !== 'visualization.rendered') return undefined;
  const visualization = decodeVisualization(render.payload.render.text);
  const step = visualization.steps[selection.step];
  if (!step) return undefined;
  const selected = new Set(selection.instances);
  const elements = step.instances.flatMap((instance) => {
    if (!selected.has(instance.id)) return [];
    const element = visualization.elements.find(({ id }) => id === instance.elementId);
    return element
      ? [
          {
            instanceId: instance.id,
            ...element,
            findings: visualization.findings.filter(
              (finding) =>
                finding.findingElementIds.includes(element.id) &&
                finding.findingStepIndices.includes(selection.step)
            )
          }
        ]
      : [];
  });
  return {
    ...selection,
    stepLabel: step.label,
    renderSummary: renderSummary(render),
    elements
  };
}

function projectWorkspace(snapshot: ProjectSnapshot): AiWorkspace {
  return {
    entryArtifactId: snapshot.entryArtifactId,
    artifacts: Object.values(snapshot.artifacts).map((artifact) => ({
      artifactId: artifact.artifactId,
      path: artifact.path,
      language: artifact.language,
      source: artifact.content.text,
      sha256: artifact.content.sha256
    }))
  };
}

function feedbackMessage(event: ProjectEventOf<'feedback.submitted'>): string {
  const details = [event.payload.text];
  if (event.payload.focus.length > 0) {
    details.push(`Focused timeline events: ${event.payload.focus.join(', ')}`);
  }
  if (event.payload.selection) {
    const selection = event.payload.selection;
    details.push(
      `Visual selection in render ${selection.render}, step ${selection.step}: instances ${selection.instances.join(', ')}`
    );
  }
  return details.filter(Boolean).join('\n\n');
}

function renderSummary(event: ProjectEventOf<'visualization.rendered'>): AiRenderSummary {
  return {
    id: event.id,
    seed: event.payload.seed,
    sourceSha256: event.payload.source.sha256,
    renderSha256: event.payload.render.sha256,
    ...(event.payload.provenance ? { provenance: event.payload.provenance } : {}),
    ...(event.payload.targetDiagnostics
      ? { targetDiagnostics: event.payload.targetDiagnostics }
      : {})
  };
}

function shortHash(sha256: string): string {
  return sha256.slice(0, 12);
}
