import type { ArtifactContext } from '$lib/artifacts/types';
import type { ChatMessage } from '$lib/chat/types';

export type ChatbotRequest = {
  messages: ChatMessage[];
  artifact: ArtifactContext;
};

export type ChatbotResult = {
  reply: string;
  sourceArtifactContent?: string;
};

export interface Chatbot {
  readonly id: string;
  generateReply(request: ChatbotRequest): Promise<ChatbotResult>;
}
