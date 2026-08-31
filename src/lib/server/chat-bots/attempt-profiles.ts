import type { ChatBotAttemptProfile } from './types';

/** Economical ladder retained for direct HTML generation. */
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

/**
 * Sverlin generation starts with the model that reliably follows the linear
 * DSL, then permits one stronger repair and one bounded simplification pass.
 */
export function sverlinAttemptProfiles(
  maxOutputTokens: number
): readonly [ChatBotAttemptProfile, ...ChatBotAttemptProfile[]] {
  return [
    {
      purpose: 'initial',
      parameters: { model: 'gpt-5.6-sol', reasoningEffort: 'medium', maxOutputTokens }
    },
    {
      purpose: 'repair',
      parameters: { model: 'gpt-5.6-sol', reasoningEffort: 'high', maxOutputTokens }
    },
    {
      purpose: 'fallback',
      parameters: { model: 'gpt-5.6-sol', reasoningEffort: 'xhigh', maxOutputTokens }
    }
  ];
}
