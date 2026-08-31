/** IndexedDB-backed, memory-fallback outbox for participant interaction records. */

import { openDB, type DBSchema, type IDBPDatabase } from 'idb';

import type {
  StudyInteractionEventInput,
  StudyInteractionSessionInput,
  StudyInteractionTerminal
} from '$lib/shared/study/interactions';

export type InteractionDropReason = Extract<
  StudyInteractionEventInput,
  { kind: 'recorder.dropped' }
>['payload']['reason'];

export type StoredInteractionSession = {
  session: StudyInteractionSessionInput;
  participantId: string;
  deliveryExpiresAt?: string;
  terminal?: StudyInteractionTerminal;
  blocked?: { at: string; reason: string };
};

export type StoredInteractionEvent = {
  sessionId: string;
  sequence: number;
  event: StudyInteractionEventInput;
  byteLength: number;
};

type StoreResult = {
  stored: boolean;
  dropped: Partial<Record<StudyInteractionEventInput['kind'], number>>;
  storageUnavailable: boolean;
};

interface InteractionDatabase extends DBSchema {
  sessions: {
    key: string;
    value: StoredInteractionSession;
  };
  events: {
    key: [string, number];
    value: StoredInteractionEvent;
    indexes: { 'by-session': string };
  };
}

export interface InteractionOutbox {
  putSession(value: StoredInteractionSession): Promise<void>;
  finalize(sessionId: string, terminal: StudyInteractionTerminal): Promise<void>;
  block(sessionId: string, reason: string, at: string): Promise<void>;
  putEvent(value: StoredInteractionEvent, byteLimit: number): Promise<StoreResult>;
  replaceEvent(value: StoredInteractionEvent): Promise<void>;
  sessions(): Promise<StoredInteractionSession[]>;
  events(sessionId: string): Promise<StoredInteractionEvent[]>;
  acknowledge(sessionId: string, acceptedThrough: number): Promise<void>;
  complete(sessionId: string): Promise<void>;
  abandon(sessionId: string): Promise<void>;
}

/** Prefer durable storage while making every failure degrade to bounded memory. */
export class ResilientInteractionOutbox implements InteractionOutbox {
  #database?: Promise<IDBPDatabase<InteractionDatabase>>;
  #durable = true;
  #hydratedEvents = false;
  #memorySessions = new Map<string, StoredInteractionSession>();
  #memoryEvents = new Map<string, StoredInteractionEvent>();

  async putSession(value: StoredInteractionSession): Promise<void> {
    this.#memorySessions.set(value.session.id, value);
    await this.#withDatabase((database) => database.put('sessions', value));
  }

  async finalize(sessionId: string, terminal: StudyInteractionTerminal): Promise<void> {
    const sessions = await this.sessions();
    const value = sessions.find(({ session }) => session.id === sessionId);
    if (!value) return;
    await this.putSession({ ...value, terminal });
  }

  async block(sessionId: string, reason: string, at: string): Promise<void> {
    const sessions = await this.sessions();
    const value = sessions.find(({ session }) => session.id === sessionId);
    if (!value) return;
    await this.putSession({ ...value, blocked: { at, reason } });
  }

  async putEvent(value: StoredInteractionEvent, byteLimit: number): Promise<StoreResult> {
    this.#memoryEvents.set(eventKey(value.sessionId, value.sequence), value);
    await this.#withDatabase((database) => database.put('events', value));
    const result = await this.#enforceLimit(byteLimit);
    if (!result.stored) await this.#deleteEvent(value.sessionId, value.sequence);
    return { ...result, storageUnavailable: !this.#durable };
  }

  async replaceEvent(value: StoredInteractionEvent): Promise<void> {
    await this.#replaceEvent(value);
  }

  async sessions(): Promise<StoredInteractionSession[]> {
    const durable = await this.#withDatabase((database) => database.getAll('sessions'));
    if (durable) {
      this.#memorySessions.clear();
      for (const value of durable) this.#memorySessions.set(value.session.id, value);
    }
    return [...this.#memorySessions.values()].toSorted((left, right) =>
      left.session.clientStartedAt.localeCompare(right.session.clientStartedAt)
    );
  }

  async events(sessionId: string): Promise<StoredInteractionEvent[]> {
    const durable = await this.#withDatabase((database) =>
      database.getAllFromIndex('events', 'by-session', sessionId)
    );
    if (durable) {
      for (const [key, value] of this.#memoryEvents) {
        if (value.sessionId === sessionId) this.#memoryEvents.delete(key);
      }
      for (const value of durable) {
        this.#memoryEvents.set(eventKey(value.sessionId, value.sequence), value);
      }
    }
    return [...this.#memoryEvents.values()]
      .filter((value) => value.sessionId === sessionId)
      .toSorted((left, right) => left.sequence - right.sequence);
  }

  async acknowledge(sessionId: string, acceptedThrough: number): Promise<void> {
    const events = await this.events(sessionId);
    const acknowledged = events.filter(({ sequence }) => sequence <= acceptedThrough);
    for (const value of acknowledged) {
      this.#memoryEvents.delete(eventKey(sessionId, value.sequence));
    }
    await this.#withDatabase(async (database) => {
      const transaction = database.transaction('events', 'readwrite');
      await Promise.all([
        ...acknowledged.map(({ sequence }) => transaction.store.delete([sessionId, sequence])),
        transaction.done
      ]);
    });
  }

  async complete(sessionId: string): Promise<void> {
    const session = (await this.sessions()).find(({ session }) => session.id === sessionId);
    if (!session?.terminal || (await this.events(sessionId)).length) return;
    this.#memorySessions.delete(sessionId);
    await this.#withDatabase((database) => database.delete('sessions', sessionId));
  }

  async abandon(sessionId: string): Promise<void> {
    const events = await this.events(sessionId);
    this.#memorySessions.delete(sessionId);
    for (const value of events) this.#memoryEvents.delete(eventKey(sessionId, value.sequence));
    await this.#withDatabase(async (database) => {
      const transaction = database.transaction(['sessions', 'events'], 'readwrite');
      await Promise.all([
        transaction.objectStore('sessions').delete(sessionId),
        ...events.map(({ sequence }) =>
          transaction.objectStore('events').delete([sessionId, sequence])
        ),
        transaction.done
      ]);
    });
  }

  async #enforceLimit(byteLimit: number): Promise<StoreResult> {
    if (!this.#hydratedEvents) {
      const sessions = await this.sessions();
      await Promise.all(sessions.map(({ session }) => this.events(session.id)));
      this.#hydratedEvents = true;
    }
    const values = [...this.#memoryEvents.values()].toSorted(
      (left, right) =>
        left.event.clientOccurredAt.localeCompare(right.event.clientOccurredAt) ||
        left.sequence - right.sequence
    );
    let total = values.reduce((sum, value) => sum + value.byteLength, 0);
    const dropped: StoreResult['dropped'] = {};
    const removable = [
      ...values.filter(({ event }) => event.kind === 'pointer.path'),
      ...coalescibleWorkspaceStates(values)
    ];
    for (const value of removable) {
      if (total <= byteLimit) break;
      const replacement = droppedStoredRecord(value, 'outbox-limit');
      await this.#replaceEvent(replacement);
      total -= value.byteLength - replacement.byteLength;
      dropped[value.event.kind] = (dropped[value.event.kind] ?? 0) + 1;
    }
    return { stored: total <= byteLimit, dropped, storageUnavailable: !this.#durable };
  }

  async #replaceEvent(value: StoredInteractionEvent): Promise<void> {
    this.#memoryEvents.set(eventKey(value.sessionId, value.sequence), value);
    await this.#withDatabase((database) => database.put('events', value));
  }

  async #deleteEvent(sessionId: string, sequence: number): Promise<void> {
    this.#memoryEvents.delete(eventKey(sessionId, sequence));
    await this.#withDatabase((database) => database.delete('events', [sessionId, sequence]));
  }

  async #withDatabase<T>(operation: (database: IDBPDatabase<InteractionDatabase>) => Promise<T>) {
    if (!this.#durable) return undefined;
    if (typeof indexedDB === 'undefined') {
      this.#durable = false;
      return undefined;
    }
    try {
      this.#database ??= openDB<InteractionDatabase>('sverlin-project-interactions', 1, {
        upgrade(database) {
          database.createObjectStore('sessions', { keyPath: 'session.id' });
          const events = database.createObjectStore('events', {
            keyPath: ['sessionId', 'sequence']
          });
          events.createIndex('by-session', 'sessionId');
        }
      });
      return await operation(await this.#database);
    } catch {
      this.#durable = false;
      this.#database = undefined;
      return undefined;
    }
  }
}

function coalescibleWorkspaceStates(
  values: readonly StoredInteractionEvent[]
): StoredInteractionEvent[] {
  const latestBySession = new Map<string, number>();
  for (const value of values) {
    if (value.event.kind === 'workspace.state')
      latestBySession.set(value.sessionId, value.sequence);
  }
  return values.filter(
    (value) =>
      value.event.kind === 'workspace.state' &&
      value.event.payload.reason === 'changed' &&
      value.sequence !== latestBySession.get(value.sessionId)
  );
}

function eventKey(sessionId: string, sequence: number): string {
  return `${sessionId}:${sequence}`;
}

/** Replace one unavailable record without opening a gap in the session sequence. */
export function droppedStoredRecord(
  value: StoredInteractionEvent,
  reason: InteractionDropReason
): StoredInteractionEvent {
  const event: StudyInteractionEventInput = {
    sequence: value.event.sequence,
    elapsedMs: value.event.elapsedMs,
    clientOccurredAt: value.event.clientOccurredAt,
    projectHead: value.event.projectHead,
    kind: 'recorder.dropped',
    payload: { counts: { [value.event.kind]: 1 }, reason }
  };
  return {
    ...value,
    event,
    byteLength: new TextEncoder().encode(JSON.stringify(event)).byteLength
  };
}
