/** Pure presentation-buffer projections over the immutable project Timeline. */

import type { ProjectEvent } from './events';
import type { ProjectDocument } from './model';
import { projectSnapshotAt } from './projection';

/** One current-source presentation that has not been consumed by an explicit advance action. */
export type AvailablePresentation = {
  eventId: number;
  presentationId: string;
};

/** Current state of a configured ahead-of-time presentation buffer. */
export type PresentationBufferState = {
  sourceSha256?: string;
  available: AvailablePresentation[];
  consumedPresentationIds: Set<string>;
  deficit: number;
};

/** Derive current-source availability without maintaining a second mutable queue. */
export function presentationBufferState(
  value: ProjectDocument | readonly ProjectEvent[],
  target: number,
  sourceSha256?: string
): PresentationBufferState {
  const events = 'events' in value ? value.events : value;
  const currentSourceSha256 =
    sourceSha256 ?? ('events' in value ? activeSourceSha256(value) : undefined);
  const consumedPresentationIds = new Set(
    events.flatMap((event) => {
      if (event.type === 'visualization.preference-recorded') return event.payload.presentations;
      return event.type === 'visualization.candidates-advanced' ? event.payload.presentations : [];
    })
  );
  const available = events.flatMap<AvailablePresentation>((event) => {
    if (event.type === 'visualization.presented') {
      const presentation = event.payload.presentation;
      if (
        presentation.format !== 'sverlin-ir-v1' ||
        presentation.source.sha256 !== currentSourceSha256 ||
        consumedPresentationIds.has(presentation.presentationId)
      ) {
        return [];
      }
      return [{ eventId: event.id, presentationId: presentation.presentationId }];
    }
    return [];
  });
  return {
    sourceSha256: currentSourceSha256,
    available,
    consumedPresentationIds,
    deficit: Math.max(0, target - available.length)
  };
}

function activeSourceSha256(document: ProjectDocument): string | undefined {
  const snapshot = projectSnapshotAt(document);
  return snapshot.artifacts[snapshot.entryArtifactId]?.content.sha256;
}
