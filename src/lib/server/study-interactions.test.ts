import { beforeEach, describe, expect, it } from 'vitest';

import {
  consumeStudyInteractionBatchAllowance,
  resetStudyInteractionRateLimits
} from './study-interactions';

describe('project interaction ingestion limits', () => {
  beforeEach(() => resetStudyInteractionRateLimits());

  it('limits a participant to thirty batches in one minute', () => {
    for (let index = 0; index < 30; index += 1) {
      expect(consumeStudyInteractionBatchAllowance('participant-one', 1_000)).toBe(true);
    }
    expect(consumeStudyInteractionBatchAllowance('participant-one', 1_000)).toBe(false);
    expect(consumeStudyInteractionBatchAllowance('participant-one', 61_000)).toBe(true);
  });

  it('keeps independent participant allowances isolated', () => {
    for (let index = 0; index < 30; index += 1) {
      consumeStudyInteractionBatchAllowance('participant-one', 1_000);
    }

    expect(consumeStudyInteractionBatchAllowance('participant-two', 1_000)).toBe(true);
  });
});
