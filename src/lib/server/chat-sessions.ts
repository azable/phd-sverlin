import type { ChatMessage, ChatPageState } from '$lib/chat/types';
import { getArtifactSyncState, resetArtifactToInitial } from '$lib/server/artifacts/store';

const initialMessage: ChatMessage = {
  role: 'assistant',
  content: 'Hi! Ask me anything about this workspace.'
};

let messages: ChatMessage[] = [initialMessage];

export function getChatState(): ChatPageState {
  return structuredClone({ messages, artifact: getArtifactSyncState() });
}

export function saveChatMessages(nextMessages: ChatMessage[]) {
  messages = structuredClone(nextMessages);
}

export function clearChatState() {
  messages = [initialMessage];
  resetArtifactToInitial();
}
