import { describe, expect, it } from 'vitest';

import { actionFailureMessage, participantCredentials } from './action-result';

describe('actionFailureMessage', () => {
  it('keeps a specific action failure message', () => {
    expect(
      actionFailureMessage(
        { type: 'failure', status: 400, data: { error: 'Enter a valid value.' } },
        'The action failed.'
      )
    ).toBe('Enter a valid value.');
  });

  it('uses the fallback for empty or unavailable errors', () => {
    expect(
      actionFailureMessage(
        { type: 'failure', status: 400, data: { error: '' } },
        'The action failed.'
      )
    ).toBe('The action failed.');
    expect(
      actionFailureMessage({ type: 'error', status: 500, error: new Error() }, 'The action failed.')
    ).toBe('The action failed.');
  });

  it('does not report successful or redirecting actions as failures', () => {
    expect(
      actionFailureMessage({ type: 'success', status: 200, data: {} }, 'The action failed.')
    ).toBeUndefined();
    expect(
      actionFailureMessage(
        { type: 'redirect', status: 303, location: '/admin' },
        'The action failed.'
      )
    ).toBeUndefined();
  });
});

describe('participantCredentials', () => {
  it('reads one-time credentials from a successful participant action', () => {
    expect(
      participantCredentials({
        type: 'success',
        status: 200,
        data: { participantId: 'P-101', participantPassword: 'one-time-secret' }
      })
    ).toEqual({ participantId: 'P-101', password: 'one-time-secret' });
  });

  it('rejects incomplete or unsuccessful action data', () => {
    expect(
      participantCredentials({ type: 'success', status: 200, data: { participantId: 'P-101' } })
    ).toBeUndefined();
    expect(
      participantCredentials({ type: 'failure', status: 400, data: { error: 'Failed.' } })
    ).toBeUndefined();
  });
});
