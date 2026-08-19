import { getArtifactContext } from '$lib/server/artifacts/store';
import { updateArtifactFromChat } from '$lib/server/artifacts/service';
import { getChatState, saveChatMessages } from '$lib/server/chat-sessions';
import { getChatbot } from '$lib/server/chatbot/registry';

import type { ChatPageState } from '$lib/chat/types';

export { InvalidSourceArtifactError } from '$lib/server/artifacts/service';

export async function sendChatMessage(message: string): Promise<ChatPageState> {
  const current = getChatState();
  const chatTurnId = crypto.randomUUID();
  const result = await getChatbot().generateReply({
    messages: [...current.messages, { role: 'user', content: message }],
    artifact: getArtifactContext()
  });

  const nextMessages = [
    ...current.messages,
    { role: 'user' as const, content: message },
    { role: 'assistant' as const, content: result.reply }
  ];
  if (result.sourceArtifactContent !== undefined) {
    updateArtifactFromChat(result.sourceArtifactContent, current.artifact.headRevision, chatTurnId);
  }

  saveChatMessages(nextMessages);
  return getChatState();
}
