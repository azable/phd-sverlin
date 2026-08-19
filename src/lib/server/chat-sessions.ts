export type ChatMessage = {
  role: 'user' | 'assistant';
  content: string;
};

const initialMessage: ChatMessage = {
  role: 'assistant',
  content: 'Hi! Ask me anything about this workspace.'
};

let messages: ChatMessage[] = [initialMessage];

export function getChatMessages(): ChatMessage[] {
  return [...messages];
}

export function saveChatMessages(nextMessages: ChatMessage[]) {
  messages = [...nextMessages];
}

export function clearChatMessages() {
  messages = [initialMessage];
}
