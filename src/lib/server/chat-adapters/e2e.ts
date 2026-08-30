import type { ChatAdapter } from './types';

/** Whether the explicitly test-only deterministic assistant may replace a live provider. */
export function e2eChatAdapterEnabled(environment: NodeJS.ProcessEnv = process.env): boolean {
  return (
    (environment.NODE_ENV === 'development' || environment.NODE_ENV === 'test') &&
    environment.SVERLIN_E2E_AUTH_BYPASS === 'true' &&
    environment.SVERLIN_E2E_ASSISTANT_BYPASS === 'true'
  );
}

/** Deterministic conversation-only responses for browser tests of the async operation lifecycle. */
export const e2eChatAdapter: ChatAdapter = {
  id: 'e2e-deterministic',
  async generateReply(request) {
    if (!e2eChatAdapterEnabled()) {
      throw new Error('The deterministic assistant is available only to the E2E test server.');
    }
    const reply = [{ type: 'markdown', text: 'Thanks, I have noted that feedback.' }];
    return {
      output:
        request.responseFormat.name === 'html_visualization_turn'
          ? { reply, candidates: [], recovery: null }
          : { reply, candidateAction: 'none', sourceArtifactContent: null, recovery: null },
      generation: { model: 'e2e-deterministic' }
    };
  },
  requestTimeoutMs: () => 0
};
