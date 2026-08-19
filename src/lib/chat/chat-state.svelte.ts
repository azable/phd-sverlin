import type { ChatPageState } from './types';

export type ChatMessageView = ChatPageState['messages'][number] & { id: number };

export class ChatState {
  messages = $state<ChatMessageView[]>([]);
  artifact = $state<ChatPageState['artifact'] | null>(null);
  streamVersion = $state(0);
  draft = $state('');
  sending = $state(false);
  error = $state<string | null>(null);

  #nextMessageId = 1;
  #submittedDraft = '';

  constructor(initialState: ChatPageState) {
    this.applyServerState(initialState);
  }

  beginSubmit() {
    const message = this.draft.trim();

    if (!message || this.sending) return false;

    this.#submittedDraft = this.draft;
    this.draft = '';
    this.error = null;
    this.sending = true;
    this.messages = [
      ...this.messages,
      { id: this.#nextMessageId++, role: 'user', content: message }
    ];
    return true;
  }

  beginReset() {
    if (this.sending) return false;

    this.draft = '';
    this.error = null;
    this.sending = true;
    return true;
  }

  applyServerState(nextState: ChatPageState) {
    this.messages = nextState.messages.map((message) => ({
      ...message,
      id: this.#nextMessageId++
    }));
    this.artifact = nextState.artifact;
    this.streamVersion = nextState.artifact.streamVersion;
    this.sending = false;
    this.error = null;
  }

  applyActionError(message: string) {
    this.draft = this.#submittedDraft;
    this.error = message;
    this.sending = false;
  }
}
