import { fail } from '@sveltejs/kit';

import { clearChatState, getChatState } from '$lib/server/chat-sessions';
import { InvalidSourceArtifactError, sendChatMessage } from '$lib/server/chat-service';
import { OpenAIConfigurationError } from '$lib/server/openai-chat';

import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = () => getChatState();

export const actions: Actions = {
  reset: async () => {
    await clearChatState();
    return getChatState();
  },
  send: async ({ request }) => {
    const formData = await request.formData();
    const rawMessage = formData.get('message');

    if (typeof rawMessage !== 'string' || !rawMessage.trim()) {
      return fail(400, { error: '`message` must be a non-empty string.' });
    }

    try {
      return await sendChatMessage(rawMessage.trim());
    } catch (error) {
      if (error instanceof OpenAIConfigurationError) {
        return fail(503, { error: error.message });
      }

      if (error instanceof InvalidSourceArtifactError) {
        return fail(502, { error: error.message });
      }

      if (error instanceof Error && error.name === 'ChatContextOverflowError') {
        return fail(413, { error: error.message });
      }

      console.error('Chat action failed.', error);
      return fail(502, { error: 'The chat service is unavailable.' });
    }
  }
};
