export type ChatMessage = {
  id: number;
  role: 'user' | 'assistant';
  content: string;
};

type ChatMessagePayload = Omit<ChatMessage, 'id'>;

export class ChatState {
  messages = $state<ChatMessage[]>([]);
  draft = $state('');
  sending = $state(false);
  error = $state<string | null>(null);

  #nextMessageId = 1;

  async load() {
    try {
      const response = await fetch('/api/chat');
      const payload = await this.readPayload(response, 'Unable to load chat history.');

      this.applyMessages(payload.messages);
    } catch (error) {
      this.error = error instanceof Error ? error.message : 'Unable to load chat history.';
    }
  }

  async submit() {
    const message = this.draft.trim();

    if (!message || this.sending) return;

    const submittedDraft = this.draft;
    this.draft = '';
    this.error = null;
    this.sending = true;
    this.messages = [
      ...this.messages,
      { id: this.#nextMessageId++, role: 'user', content: message }
    ];

    try {
      const response = await fetch('/api/chat', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ message })
      });
      const payload = await this.readPayload(response, 'Chat request failed.');

      this.applyMessages(payload.messages);
    } catch (error) {
      this.draft = submittedDraft;
      this.error = error instanceof Error ? error.message : 'Chat request failed.';
    } finally {
      this.sending = false;
    }
  }

  async reset() {
    if (this.sending) return;

    this.draft = '';
    this.error = null;

    try {
      const response = await fetch('/api/chat', { method: 'DELETE' });
      const payload = await this.readPayload(response, 'Unable to reset chat.');

      this.applyMessages(payload.messages);
    } catch (error) {
      this.error = error instanceof Error ? error.message : 'Unable to reset chat.';
    }
  }

  private async readPayload(response: Response, fallback: string) {
    const payload = (await response.json()) as {
      messages?: ChatMessagePayload[];
      error?: string;
    };

    if (!response.ok || !Array.isArray(payload.messages)) {
      throw new Error(payload.error ?? fallback);
    }

    return { messages: payload.messages };
  }

  private applyMessages(nextMessages: ChatMessagePayload[]) {
    this.messages = nextMessages.map((message) => ({ ...message, id: this.#nextMessageId++ }));
  }
}
