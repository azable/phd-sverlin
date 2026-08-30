/** Reactive selection state shared by the Timeline and visualization stage. */

import type { ProjectEvent } from '$lib/shared/projects/events';
import type { PresentationLayout } from '$lib/shared/presentations';

import {
  compatibleSverlinPair,
  latestPresentations,
  presentationGroup,
  presentationsById,
  timelinePresentations,
  type TimelinePresentation
} from './presentation-history';

/** Coordinates generated sets, custom pairs, and live-head following. */
export class PresentationSelection {
  selectedIds = $state.raw<string[]>([]);
  followingLatest = $state(true);
  notice = $state<string | null>(null);

  /** Presentations currently shown on the stage. */
  selected(events: readonly ProjectEvent[], layout: PresentationLayout): TimelinePresentation[] {
    const all = timelinePresentations(events);
    if (this.followingLatest) return latestPresentations(all, layout);
    return presentationsById(all, this.selectedIds).slice(0, layout === 'comparison' ? 2 : 1);
  }

  /** Activate a generated set, or use Shift to build a compatible historical pair. */
  activate(
    presentation: TimelinePresentation,
    events: readonly ProjectEvent[],
    layout: PresentationLayout,
    extend = false
  ): void {
    const all = timelinePresentations(events);
    if (extend) {
      if (layout !== 'comparison') {
        this.notice = 'Comparisons are unavailable in single-view mode.';
        return;
      }
      const activeIds = this.followingLatest
        ? latestPresentations(all, layout).map(({ presentation: value }) => value.presentationId)
        : this.selectedIds;
      this.extend(presentation, all, activeIds);
      return;
    }
    const next = presentationGroup(all, presentation, layout).map(
      ({ presentation: value }) => value.presentationId
    );
    this.setIds(next);
    this.followingLatest = sameIds(
      next,
      latestPresentations(all, layout).map(({ presentation: value }) => value.presentationId)
    );
    this.notice = null;
  }

  /** Resume automatic selection of newly generated output. */
  returnToLatest(): void {
    this.followingLatest = true;
    this.notice = null;
  }

  private extend(
    selected: TimelinePresentation,
    all: readonly TimelinePresentation[],
    activeIds: readonly string[]
  ): void {
    const id = selected.presentation.presentationId;
    if (activeIds.includes(id)) {
      this.setIds(activeIds.filter((selectedId) => selectedId !== id));
      this.followingLatest = false;
      this.notice = null;
      return;
    }
    if (selected.presentation.format !== 'sverlin-ir-v1') {
      this.notice = 'HTML visualizations can only be viewed one at a time.';
      return;
    }
    if (activeIds.length >= 2) {
      this.notice = 'Deselect one visualization before adding another.';
      return;
    }
    const current = presentationsById(all, activeIds);
    if (current.length === 1 && !compatibleSverlinPair(current[0], selected)) {
      this.notice = 'Only compatible versions of the same visualization can be compared.';
      return;
    }
    this.setIds([...activeIds, id]);
    this.followingLatest = false;
    this.notice = null;
  }

  private setIds(ids: readonly string[]): void {
    if (sameIds(this.selectedIds, ids)) return;
    this.selectedIds = [...ids];
  }
}

function sameIds(left: readonly string[], right: readonly string[]): boolean {
  return left.length === right.length && left.every((id, index) => id === right[index]);
}
