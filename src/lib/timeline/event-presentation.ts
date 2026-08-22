import { eventLabel } from '$lib/projects/project';
import type { ProjectEvent, ProjectEventType } from '$lib/projects/types';

export type TimelineEventIcon =
  | 'assistant'
  | 'code'
  | 'default'
  | 'failure'
  | 'message'
  | 'visualization';

export type TimelineEventPresentation = {
  title: string;
  detail: string;
  icon: TimelineEventIcon;
  progress: string;
  restorable: boolean;
  tone: 'default' | 'destructive';
};

type PresentationDetails = Omit<TimelineEventPresentation, 'title'>;
type Presenters = {
  [Type in ProjectEventType]: (event: Extract<ProjectEvent, { type: Type }>) => PresentationDetails;
};

const presenters = {
  'project.created': (event) =>
    details(event.payload.title, 'default', 'default', 'Creating the project…'),
  'project.renamed': (event) =>
    details(event.payload.title, 'default', 'default', 'Updating the project…'),
  'feedback.submitted': (event) =>
    details(
      event.payload.text ?? `${event.payload.attachments.length} feedback attachment(s)`,
      'message',
      'default',
      'Feedback recorded…'
    ),
  'ai.generation-requested': (event) =>
    details(
      `${event.payload.requestedModel} · ${event.payload.purpose}`,
      'assistant',
      'default',
      event.payload.purpose === 'repair'
        ? 'Repairing generated source…'
        : 'Generating a visualization…'
    ),
  'ai.generation-succeeded': (event) =>
    details(
      `${event.payload.model ?? event.payload.requestedModel} · ${event.payload.durationMs} ms`,
      'assistant',
      'default',
      'Checking the generated source…'
    ),
  'ai.generation-failed': (event) =>
    details(event.payload.message, 'failure', 'destructive', 'Recording the AI failure…'),
  'visualization.render-requested': (event) =>
    details(
      `${event.payload.purpose} · seed ${event.payload.seed}`,
      'visualization',
      'default',
      'Preparing the visualization…'
    ),
  'compilation.requested': (event) =>
    details(
      `${event.payload.sourceLabel} · seed ${event.payload.seed}`,
      'code',
      'default',
      'Compiling generated source…'
    ),
  'compilation.succeeded': (event) =>
    details(
      `${event.payload.durationMs} ms · ${event.payload.renderSha256.slice(0, 8)}`,
      'code',
      'default',
      'Compilation succeeded; activating…'
    ),
  'compilation.failed': (event) =>
    details(
      event.payload.diagnostics[0]?.message ?? event.payload.error ?? event.payload.failureKind,
      'failure',
      'destructive',
      event.payload.repairEligible
        ? 'Compilation failed; checking repair…'
        : 'Recording the compilation failure…'
    ),
  'artifact.version-created': (event) =>
    details(
      event.payload.changes
        .map((change) =>
          change.operation === 'delete' ? `Deleted ${change.artifactId}` : change.artifact.path
        )
        .join(', '),
      'code',
      'default',
      'Loading the updated artifact…',
      true
    ),
  'visualization.rendered': (event) =>
    details(
      `seed ${event.payload.seed} · ${event.payload.renderSha256.slice(0, 8)}`,
      'visualization',
      'default',
      'Loading the visualization…',
      true
    ),
  'assistant.responded': (event) =>
    details(event.payload.text, 'assistant', 'default', 'Finishing…'),
  'system.notified': (event) =>
    details(
      event.payload.message,
      event.payload.severity === 'error' ? 'failure' : 'default',
      event.payload.severity === 'error' ? 'destructive' : 'default',
      event.payload.severity === 'error' ? 'Finishing with an error…' : 'Finishing…'
    )
} satisfies Presenters;

export function presentProjectEvent(event: ProjectEvent): TimelineEventPresentation {
  const present = presenters[event.type] as (value: ProjectEvent) => PresentationDetails;
  return { title: eventLabel(event), ...present(event) };
}

function details(
  detail: string,
  icon: TimelineEventIcon,
  tone: TimelineEventPresentation['tone'],
  progress: string,
  restorable = false
): PresentationDetails {
  return { detail, icon, progress, restorable, tone };
}
