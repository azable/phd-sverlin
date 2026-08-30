import { describe, expect, it } from 'vitest';

import { completePollSnapshot, selectPollSnapshot } from './poll-snapshot';

describe('poll snapshots', () => {
  it('uses live poll data while the originating page data is current', () => {
    const page = [{ id: 'participant-one', status: 'not-started' }];
    const polled = [{ id: 'participant-one', status: 'in-progress' }];

    expect(selectPollSnapshot(page, { base: page, value: polled })).toBe(polled);
  });

  it('lets an action invalidation replace an older poll snapshot immediately', () => {
    const beforeAction = [{ id: 'participant-one' }];
    const afterDelete: typeof beforeAction = [];
    const snapshot = { base: beforeAction, value: beforeAction };

    expect(selectPollSnapshot(afterDelete, snapshot)).toBe(afterDelete);
    expect(completePollSnapshot(beforeAction, afterDelete, beforeAction)).toBeUndefined();
  });
});
