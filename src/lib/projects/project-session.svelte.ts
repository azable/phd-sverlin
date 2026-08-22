import { deserialize } from '$app/forms';
import { invalidateAll } from '$app/navigation';

import { projectEventNeedsHydration } from './event-policy';
import { normalizeProjectEventV1 } from './schema';
import type {
  FeedbackAttachment,
  ProjectActionAck,
  ProjectActionName,
  ProjectDocument,
  ProjectEvent,
  ProjectPageState,
  TimelineReferenceAttachment
} from './types';

export type PendingProjectAction = {
  action: ProjectActionName;
  correlationId: string;
  startedAfterSequence: number;
};

export type ProjectConnectionState = 'connecting' | 'open' | 'reconnecting';

export class ProjectSession {
  pending = $state.raw<PendingProjectAction | null>(null);
  connection = $state<ProjectConnectionState>('connecting');
  error = $state<string | null>(null);
  feedbackDraft = $state('');
  attachments = $state.raw<FeedbackAttachment[]>([]);
  #streamedEvents = $state.raw<ProjectEvent[]>([]);
  #refreshTail: Promise<void> = Promise.resolve();

  constructor(private readonly getPage: () => ProjectPageState) {}

  get page() {
    return this.getPage();
  }

  get events() {
    return mergeProjectEvents(this.page.document.events, this.#streamedEvents);
  }

  get document(): ProjectDocument {
    return { ...this.page.document, events: this.events };
  }

  get snapshot() {
    return this.page.snapshot;
  }

  get trace() {
    return this.page.trace;
  }

  get headEventId() {
    return this.events.at(-1)!.eventId;
  }

  get cursorEventId() {
    return this.atHead ? this.headEventId : this.page.cursorEventId;
  }

  get atHead() {
    return this.page.cursorEventId === this.page.headEventId;
  }

  get pendingEvent() {
    const pending = this.pending;
    if (!pending) return undefined;
    return this.events.findLast(
      (event) =>
        event.sequence > pending.startedAfterSequence &&
        event.correlationId === pending.correlationId
    );
  }

  connectLive() {
    const projectId = this.page.document.projectId;
    const after = this.events.at(-1)!.sequence;
    const path = `/projects/${encodeURIComponent(projectId)}/events?after=${after}`;
    const source = new EventSource(path);
    this.connection = 'connecting';

    const receiveEvent = (message: MessageEvent<string>) => {
      try {
        this.ingest(normalizeProjectEventV1(JSON.parse(message.data)));
      } catch {
        this.recoverLiveState();
      }
    };
    const ready = (message: MessageEvent<string>) => {
      try {
        const value = JSON.parse(message.data) as Record<string, unknown>;
        if (value.schemaVersion !== 1 || value.projectId !== projectId) throw new Error();
        this.connection = 'open';
      } catch {
        this.recoverLiveState();
      }
    };
    const reconnecting = () => {
      this.connection = 'reconnecting';
    };

    source.addEventListener('project-event', receiveEvent as EventListener);
    source.addEventListener('ready', ready as EventListener);
    source.addEventListener('error', reconnecting);

    return () => {
      source.removeEventListener('project-event', receiveEvent as EventListener);
      source.removeEventListener('ready', ready as EventListener);
      source.removeEventListener('error', reconnecting);
      source.close();
    };
  }

  attachTimelineEvent(eventId: string, relationship: TimelineReferenceAttachment['relationship']) {
    const existing = this.attachments.find(
      (attachment): attachment is TimelineReferenceAttachment =>
        attachment.kind === 'timeline-reference' && attachment.relationship === relationship
    );
    if (existing?.eventIds.includes(eventId)) return;
    this.attachments = existing
      ? this.attachments.map((attachment) =>
          attachment === existing
            ? { ...existing, eventIds: [...existing.eventIds, eventId] }
            : attachment
        )
      : [...this.attachments, { kind: 'timeline-reference', relationship, eventIds: [eventId] }];
  }

  removeAttachment(index: number) {
    this.attachments = this.attachments.filter((_, attachmentIndex) => attachmentIndex !== index);
  }

  async runAction(action: ProjectActionName, values: Record<string, string>) {
    if (this.pending) return false;
    const correlationId = crypto.randomUUID();
    this.pending = {
      action,
      correlationId,
      startedAfterSequence: this.events.at(-1)!.sequence
    };
    this.error = null;
    const data = new FormData();
    data.set('correlationId', correlationId);
    data.set('expectedHeadEventId', this.headEventId);
    Object.entries(values).forEach(([key, value]) => data.set(key, value));
    let succeeded = false;

    try {
      const response = await fetch(`?/${action}`, {
        method: 'POST',
        headers: { accept: 'application/json', 'x-sveltekit-action': 'true' },
        cache: 'no-store',
        body: data
      });
      const result = deserialize(await response.text());
      if (result.type === 'success') {
        const ack = result.data as ProjectActionAck;
        if (ack.correlationId !== correlationId)
          throw new Error('Project action response mismatch.');
        succeeded = true;
      } else if (result.type === 'failure') {
        this.error = actionError(result.data);
      } else {
        this.error = 'The project operation was interrupted.';
      }
    } catch (cause) {
      this.error = cause instanceof Error ? cause.message : 'The project operation failed.';
    }

    try {
      await this.refreshPage();
    } catch (cause) {
      this.error =
        cause instanceof Error ? cause.message : 'The project completed but could not be reloaded.';
      succeeded = false;
    } finally {
      this.pending = null;
    }
    return succeeded;
  }

  private ingest(event: ProjectEvent) {
    const events = this.events;
    const existing = events[event.sequence];
    if (existing) {
      if (existing.eventId !== event.eventId) {
        this.recoverLiveState();
      }
      return;
    }

    const head = events.at(-1)!;
    if (event.sequence !== head.sequence + 1 || event.parentEventId !== head.eventId) {
      this.recoverLiveState();
      return;
    }

    const baseLength = this.page.document.events.length;
    this.#streamedEvents = [
      ...this.#streamedEvents.filter(({ sequence }) => sequence >= baseLength),
      event
    ];
    if (projectEventNeedsHydration(event) && event.correlationId !== this.pending?.correlationId) {
      this.refreshFromStream();
    }
  }

  private recoverLiveState() {
    this.connection = 'reconnecting';
    this.refreshFromStream();
  }

  private refreshFromStream() {
    void this.refreshPage().then(
      () => {
        this.connection = 'open';
      },
      () => {
        this.connection = 'reconnecting';
      }
    );
  }

  private refreshPage() {
    const refresh = this.#refreshTail.then(async () => {
      await invalidateAll();
      const baseLength = this.page.document.events.length;
      this.#streamedEvents = this.#streamedEvents.filter(({ sequence }) => sequence >= baseLength);
    });
    this.#refreshTail = refresh.catch(() => undefined);
    return refresh;
  }
}

export function mergeProjectEvents(base: ProjectEvent[], streamed: ProjectEvent[]) {
  if (streamed.length === 0) return base;
  const merged = [...base];
  for (const event of streamed.toSorted((left, right) => left.sequence - right.sequence)) {
    const existing = merged[event.sequence];
    if (existing?.eventId === event.eventId) continue;
    if (event.sequence !== merged.length || event.parentEventId !== merged.at(-1)?.eventId) break;
    merged.push(event);
  }
  return merged;
}

function actionError(data: unknown) {
  if (
    typeof data === 'object' &&
    data !== null &&
    'error' in data &&
    typeof data.error === 'string'
  ) {
    return data.error;
  }
  return 'The project operation failed.';
}
