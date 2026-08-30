import { describe, expect, it } from 'vitest';

import { visualizationAttemptProfiles } from './attempt-profiles';

describe('visualization attempt profiles', () => {
  it('uses the configured four-tier escalation and fifth simplification pass', () => {
    expect(visualizationAttemptProfiles(12_000)).toEqual([
      {
        purpose: 'initial',
        parameters: {
          model: 'gpt-5.6-luna',
          reasoningEffort: 'low',
          maxOutputTokens: 12_000
        }
      },
      {
        purpose: 'repair',
        parameters: {
          model: 'gpt-5.6-sol',
          reasoningEffort: 'medium',
          maxOutputTokens: 12_000
        }
      },
      {
        purpose: 'repair',
        parameters: {
          model: 'gpt-5.6-sol',
          reasoningEffort: 'high',
          maxOutputTokens: 12_000
        }
      },
      {
        purpose: 'repair',
        parameters: {
          model: 'gpt-5.6-sol',
          reasoningEffort: 'xhigh',
          maxOutputTokens: 12_000
        }
      },
      {
        purpose: 'fallback',
        parameters: {
          model: 'gpt-5.6-sol',
          reasoningEffort: 'xhigh',
          maxOutputTokens: 12_000
        }
      }
    ]);
  });
});
