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
import { plainMessageText } from '$lib/shared/projects/events/message-content';
import type { ProjectDocument, ProjectSnapshot } from '$lib/shared/projects/model';
import type { RenderablePresentation } from '$lib/shared/presentations';
import { projectHead, projectSnapshotAt } from '$lib/shared/projects/projection';
import {
  decodeVisualization,
  type RenderInstanceId,
  type VisualElement,
  type VisualizationFinding
} from '$lib/shared/visualization';
import type { ConversationMessage } from '$lib/server/chat-bots/types';
import { resolveProjectVisualSelection } from '$lib/server/projects/visual-selection';

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
  presentationId: string;
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
  activePresentations: AiRenderSummary[];
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
  presentationIds?: readonly string[];
  visualSelections?: readonly VisualSelection[];
  interactionEventIds?: readonly EventId[];
};

/** Why the current assistant turn was started. */
export type AiInteraction =
  | { kind: 'feedback'; eventIds: EventId[] }
  | {
      kind: 'preference';
      eventId: EventId;
      preferredPresentationId: string;
      alternativePresentationId: string;
      step: number;
    }
  | {
      kind: 'batch';
      eventIds: EventId[];
      preferences: Array<{
        eventId: EventId;
        preferredPresentationId: string;
        alternativePresentationId: string;
        step: number;
      }>;
    };

/** Full retained presentation explicitly visible when the user submitted feedback. */
export type AiSelectedPresentation = {
  eventId: EventId;
  displaySetId?: string;
  presentation: RenderablePresentation;
};

/** Strongly typed, consumer-specific context supplied to the AI assistant. */
export type AiProjectContext = {
  projectId: string;
  title: string;
  headEventId: EventId;
  currentWorkspace: AiWorkspace;
  activePresentations: AiRenderSummary[];
  interfaceCapabilities: string[];
  activeVisualizationFindings: VisualizationFinding[];
  interaction: AiInteraction;
  timeline: AiTimelineEntry[];
  selected: {
    events: AiEventDetail[];
    presentations: AiSelectedPresentation[];
    visualizations: AiVisualSelection[];
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
    `Submitted structured feedback with ${event.payload.content.length} segment(s)${event.payload.focus.length ? ` focused on events ${event.payload.focus.join(', ')}` : ''}.`,
  'assistant.turn-requested': (event) =>
    `Queued assistant consideration of interaction ${event.payload.interactionEventId}.`,
  'assistant.turn-started': (event) =>
    `Started assistant consideration of interactions ${event.payload.interactionEventIds.join(', ')}.`,
  'visualization.candidates-advanced': (event) =>
    `Advanced past presentations ${event.payload.presentations.join(', ')} (${event.payload.reason}).`,
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
  'assistant.turn-requested': () => [],
  'assistant.turn-started': () => [],
  'visualization.candidates-advanced': () => [],
  'ai.generation-requested': () => [],
  'ai.generation-succeeded': () => [],
  'ai.generation-failed': () => [],
  'compilation.requested': () => [],
  'compilation.succeeded': () => [],
  'compilation.failed': () => [],
  'artifact.version-created': () => [],
  'visualization.presented': () => [],
  'visualization.preference-recorded': (event) => [
    {
      role: 'user',
      content: `I preferred presentation ${event.payload.preferred} over the alternative${event.payload.displaySetId ? ` in display set ${event.payload.displaySetId}` : ''} at step ${event.payload.step}.`
    } as const
  ],
  'assistant.responded': (event) => [
    {
      role: 'assistant',
      content: `${event.payload.inReplyTo?.length ? `[In reply to interaction events ${event.payload.inReplyTo.join(', ')}]\n` : ''}${plainMessageText(event.payload.content)}`
    } as const
  ],
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
  const interaction = assistantInteraction(document, selection.interactionEventIds ?? []);
  const visualizations = (selection.visualSelections ?? []).flatMap((visualSelection) => {
    const resolved = resolveVisualSelection(document, visualSelection);
    return resolved ? [resolved] : [];
  });

  return {
    projectId: document.projectId,
    title: snapshot.title,
    headEventId: projectHead(document).id,
    currentWorkspace: projectWorkspace(snapshot),
    activePresentations: activePresentationSummaries(snapshot),
    activeVisualizationFindings: activePresentationFindings(snapshot),
    interaction,
    interfaceCapabilities: [
      'The application owns previous/next step playback controls; never draw replacement controls inside a visualization.',
      'The participant can select compatible retained Sverlin presentations to compare a pair.',
      'A visible pair has preference controls, and a participant can select exact canvas elements and reference presentations or elements inline in messages.',
      'Sverlin projects may keep another pair generated ahead of time; ordinary conversation does not advance the visible pair.'
    ],
    timeline: document.events.map(projectAiTimelineEntry),
    selected: {
      events: selection.eventIds.map((id) => eventDetail(document, id)),
      presentations: (selection.presentationIds ?? []).map((id) =>
        selectedPresentation(document, id)
      ),
      visualizations
    }
  };
}

function assistantInteraction(
  document: ProjectDocument,
  eventIds: readonly EventId[]
): AiInteraction {
  const interactions = eventIds.map((id) => {
    const event = document.events[id - 1];
    if (
      event?.type !== 'feedback.submitted' &&
      event?.type !== 'visualization.preference-recorded'
    ) {
      throw new Error('The assistant turn references an unknown interaction event.');
    }
    return event;
  });
  const preferences = interactions.flatMap((event) => {
    if (event.type !== 'visualization.preference-recorded') return [];
    const alternativePresentationId = event.payload.presentations.find(
      (id) => id !== event.payload.preferred
    );
    if (!alternativePresentationId) {
      throw new Error('The preference interaction has no alternative presentation.');
    }
    return [
      {
        eventId: event.id,
        preferredPresentationId: event.payload.preferred,
        alternativePresentationId,
        step: event.payload.step
      }
    ];
  });
  if (interactions.length === 1 && preferences[0]) {
    return { kind: 'preference', ...preferences[0] };
  }
  if (interactions.length <= 1) return { kind: 'feedback', eventIds: [...eventIds] };
  return { kind: 'batch', eventIds: [...eventIds], preferences };
}

function selectedPresentation(document: ProjectDocument, id: string): AiSelectedPresentation {
  for (const event of document.events) {
    if (
      event.type === 'visualization.presented' &&
      event.payload.presentation.presentationId === id
    ) {
      return {
        eventId: event.id,
        displaySetId: event.payload.displaySetId,
        presentation: event.payload.presentation
      };
    }
  }
  throw new Error(`Unknown selected presentation ${id}.`);
}

function eventDetail(document: ProjectDocument, id: EventId): AiEventDetail {
  const event = document.events[id - 1];
  if (!event) throw new Error(`Unknown selected event ${id}.`);
  const snapshot = projectSnapshotAt(document, id);
  return {
    event,
    workspace: projectWorkspace(snapshot),
    activePresentations: activePresentationSummaries(snapshot)
  };
}

function resolveVisualSelection(
  document: ProjectDocument,
  selection: VisualSelection
): AiVisualSelection | undefined {
  const resolved = resolveProjectVisualSelection(document, selection);
  const { visualization, step } = resolved;
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
    ...resolved.selection,
    stepLabel: step.label,
    renderSummary: {
      id: resolved.event.id,
      presentationId: resolved.event.payload.presentation.presentationId,
      seed: resolved.seed,
      sourceSha256: resolved.sourceSha256,
      renderSha256: resolved.renderSha256,
      ...(resolved.provenance ? { provenance: resolved.provenance } : {}),
      ...(resolved.targetDiagnostics ? { targetDiagnostics: resolved.targetDiagnostics } : {})
    },
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
  const details = [plainMessageText(event.payload.content)];
  if (event.payload.focus.length > 0) {
    details.push(`Focused timeline events: ${event.payload.focus.join(', ')}`);
  }
  return details.filter(Boolean).join('\n\n');
}

function renderSummary(
  event: ProjectEventOf<'visualization.presented'>
): AiRenderSummary | undefined {
  const presentation = event.payload.presentation;
  if (presentation.format !== 'sverlin-ir-v1') return undefined;
  return {
    id: event.id,
    presentationId: presentation.presentationId,
    seed: presentation.seed,
    sourceSha256: presentation.source.sha256,
    renderSha256: presentation.render.sha256,
    ...(presentation.provenance ? { provenance: presentation.provenance } : {}),
    ...(presentation.targetDiagnostics ? { targetDiagnostics: presentation.targetDiagnostics } : {})
  };
}

function activePresentationSummaries(snapshot: ProjectSnapshot): AiRenderSummary[] {
  return (snapshot.activePresentationSet?.presentations ?? []).flatMap((event) => {
    const summary = renderSummary(event);
    return summary ? [summary] : [];
  });
}

function activePresentationFindings(snapshot: ProjectSnapshot): VisualizationFinding[] {
  return (snapshot.activePresentationSet?.presentations ?? []).flatMap((event) => {
    const presentation = event.payload.presentation;
    return presentation.format === 'sverlin-ir-v1'
      ? decodeVisualization(presentation.render.text).findings
      : [];
  });
}

function shortHash(sha256: string): string {
  return sha256.slice(0, 12);
}
