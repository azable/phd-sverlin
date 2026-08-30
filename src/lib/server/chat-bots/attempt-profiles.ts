import type { ChatBotAttemptProfile } from './types';

/**
 * Shared visualization-agent ladder: one economical attempt, three increasingly
 * capable repairs, then one quality-first simplification pass.
 */
export function visualizationAttemptProfiles(
  maxOutputTokens: number
): readonly [ChatBotAttemptProfile, ...ChatBotAttemptProfile[]] {
  return [
    {
      purpose: 'initial',
      parameters: { model: 'gpt-5.6-luna', reasoningEffort: 'low', maxOutputTokens }
    },
    {
      purpose: 'repair',
      parameters: { model: 'gpt-5.6-sol', reasoningEffort: 'medium', maxOutputTokens }
    },
    {
      purpose: 'repair',
      parameters: { model: 'gpt-5.6-sol', reasoningEffort: 'high', maxOutputTokens }
    },
    {
      purpose: 'repair',
      parameters: { model: 'gpt-5.6-sol', reasoningEffort: 'xhigh', maxOutputTokens }
    },
    {
      purpose: 'fallback',
      parameters: { model: 'gpt-5.6-sol', reasoningEffort: 'xhigh', maxOutputTokens }
    }
  ];
}
