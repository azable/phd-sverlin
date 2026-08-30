/**
 * Human-readable presentation metadata for immutable project events.
 *
 * @packageDocumentation
 */

import {
  matchProjectEvent,
  type ProjectEvent,
  type ProjectEventCases
} from '$lib/shared/projects/events';

/** Icon families available to Timeline event cards. */
export type TimelineEventIcon =
  | 'assistant'
  | 'code'
  | 'default'
  | 'failure'
  | 'message'
  | 'visualization';

/** Display text and styling derived from a project event. */
export type TimelineEventPresentation = {
  title: string;
  detail: string;
  icon: TimelineEventIcon;
  progress: string;
  restorable: boolean;
  tone: 'default' | 'destructive';
};

const presenters = {
  'project.created': (event) =>
    details('Project created', event.payload.title, 'default', 'Creating the project…'),
  'project.renamed': (event) =>
    details('Project renamed', event.payload.title, 'default', 'Updating the project…'),
  'operation.accepted': (event) =>
    details(
      'Operation accepted',
      operationLabel(event.payload.kind),
      'default',
      `${operationLabel(event.payload.kind)}…`
    ),
  'operation.completed': (event) =>
    details('Operation completed', operationLabel(event.payload.kind), 'default', 'Finishing…'),
  'operation.failed': (event) =>
    details(
      'Operation failed',
      event.payload.message,
      'failure',
      'Finishing with an error…',
      false,
      'destructive'
    ),
  'feedback.submitted': (event) =>
    details(
      'Feedback submitted',
      event.payload.text ??
        `${event.payload.focus.length + Number(!!event.payload.selection)} focused item(s)`,
      'message',
      'Feedback recorded…'
    ),
  'ai.generation-requested': (event) =>
    details(
      `AI generation requested · attempt ${event.payload.attempt}`,
      `${event.payload.requestedModel} · ${event.payload.purpose}`,
      'assistant',
      event.payload.purpose === 'repair'
        ? 'Repairing generated source…'
        : 'Generating a visualization…'
    ),
  'ai.generation-succeeded': (event) =>
    details(
      `AI generation completed · attempt ${event.payload.attempt}`,
      `${event.payload.model ?? event.payload.requestedModel} · ${event.payload.durationMs} ms`,
      'assistant',
      'Checking the generated source…'
    ),
  'ai.generation-failed': (event) =>
    details(
      `AI generation failed · attempt ${event.payload.attempt}`,
      event.payload.message,
      'failure',
      'Recording the AI failure…',
      false,
      'destructive'
    ),
  'compilation.requested': (event) =>
    details(
      'Compilation requested',
      `${event.payload.sourceLabel} · seed ${event.payload.seed}`,
      'code',
      'Compiling generated source…'
    ),
  'compilation.succeeded': (event) =>
    details(
      'Compilation succeeded',
      `${event.payload.durationMs} ms · ${event.payload.render.sha256.slice(0, 8)}`,
      'code',
      'Compilation succeeded; activating…'
    ),
  'compilation.failed': (event) =>
    details(
      'Compilation failed',
      event.payload.diagnostics[0]?.message ?? event.payload.error ?? event.payload.failureKind,
      'failure',
      event.payload.repairEligible
        ? 'Compilation failed; checking repair…'
        : 'Recording the compilation failure…',
      false,
      'destructive'
    ),
  'artifact.version-created': (event) =>
    details(
      'Artifact version created',
      event.payload.changes
        .map((change) =>
          change.operation === 'delete' ? `Deleted ${change.artifactId}` : change.artifact.path
        )
        .join(', '),
      'code',
      'Loading the updated artifact…',
      true
    ),
  'visualization.rendered': (event) =>
    details(
      `Visualization rendered · seed ${event.payload.seed}`,
      event.payload.render.sha256.slice(0, 8),
      'visualization',
      'Loading the visualization…',
      true
    ),
  'assistant.responded': (event) =>
    details('Assistant responded', event.payload.text, 'assistant', 'Finishing…'),
  'system.notified': (event) =>
    details(
      'System notice',
      event.payload.message,
      event.payload.severity === 'error' ? 'failure' : 'default',
      event.payload.severity === 'error' ? 'Finishing with an error…' : 'Finishing…',
      false,
      event.payload.severity === 'error' ? 'destructive' : 'default'
    )
} satisfies ProjectEventCases<TimelineEventPresentation>;

/** Convert a typed project event into its Timeline presentation. */
export function presentProjectEvent(event: ProjectEvent): TimelineEventPresentation {
  return matchProjectEvent(event, presenters);
}

function details(
  title: string,
  detail: string,
  icon: TimelineEventIcon,
  progress: string,
  restorable = false,
  tone: TimelineEventPresentation['tone'] = 'default'
): TimelineEventPresentation {
  return { title, detail, icon, progress, restorable, tone };
}

function operationLabel(kind: string): string {
  return kind.replaceAll('-', ' ');
}
