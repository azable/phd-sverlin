<script lang="ts">
  import { tick } from 'svelte';

  import BotIcon from '@lucide/svelte/icons/bot';
  import SendIcon from '@lucide/svelte/icons/send';

  import * as Alert from '$lib/components/ui/alert';
  import * as InputGroup from '$lib/components/ui/input-group';
  import { ScrollArea } from '$lib/components/ui/scroll-area';
  import { Spinner } from '$lib/components/ui/spinner';

  type Message = {
    id: number;
    role: 'user' | 'assistant';
    content: string;
  };

  let messages = $state<Message[]>([
    {
      id: 1,
      role: 'assistant',
      content: 'Hi! I’m a placeholder chatbot. Send a message and I’ll echo it back.'
    }
  ]);
  let draft = $state('');
  let sending = $state(false);
  let error = $state<string | null>(null);
  let nextMessageId = 2;
  let transcriptElement = $state<HTMLElement | null>(null);

  async function submitMessage() {
    const message = draft.trim();

    if (!message || sending) return;

    const submittedDraft = draft;
    draft = '';
    error = null;
    sending = true;
    messages = [...messages, { id: nextMessageId++, role: 'user', content: message }];
    await scrollToLatest();

    try {
      const response = await fetch('/api/chat', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ message })
      });
      const payload = (await response.json()) as { reply?: string; error?: string };

      if (!response.ok || typeof payload.reply !== 'string') {
        throw new Error(payload.error ?? 'Chat request failed.');
      }

      messages = [...messages, { id: nextMessageId++, role: 'assistant', content: payload.reply }];
      await scrollToLatest();
    } catch (err) {
      draft = submittedDraft;
      error = err instanceof Error ? err.message : 'Chat request failed.';
    } finally {
      sending = false;
    }
  }

  function handleComposerKeydown(event: KeyboardEvent) {
    if (event.key !== 'Enter' || event.shiftKey) return;

    event.preventDefault();
    void submitMessage();
  }

  async function scrollToLatest() {
    await tick();
    if (transcriptElement) transcriptElement.scrollTop = transcriptElement.scrollHeight;
  }
</script>

<section class="flex min-h-0 flex-1 flex-col" aria-label="Chat with chatbot">
  <ScrollArea bind:viewportRef={transcriptElement} class="min-h-0 flex-1 px-4 py-5">
    <div class="flex flex-col gap-4 pr-3" aria-live="polite" aria-label="Chat transcript">
      {#each messages as message (message.id)}
        <article class:flex-row-reverse={message.role === 'user'} class="flex items-start gap-3">
          <div
            class="flex size-8 shrink-0 items-center justify-center rounded-full bg-muted text-muted-foreground"
            aria-hidden="true"
          >
            {#if message.role === 'assistant'}
              <BotIcon />
            {:else}
              <span class="text-xs font-semibold">You</span>
            {/if}
          </div>
          <div
            class:bg-primary={message.role === 'user'}
            class:text-primary-foreground={message.role === 'user'}
            class="max-w-[85%] rounded-xl border bg-card px-3 py-2 text-sm leading-relaxed shadow-xs"
          >
            {message.content}
          </div>
        </article>
      {/each}

      {#if sending}
        <div class="flex items-center gap-2 text-sm text-muted-foreground" aria-live="polite">
          <Spinner />
          Thinking…
        </div>
      {/if}
    </div>
  </ScrollArea>

  <div class="flex flex-col gap-3 border-t bg-background p-4">
    {#if error}
      <Alert.Root variant="destructive">
        <Alert.Title>Unable to send message</Alert.Title>
        <Alert.Description>{error}</Alert.Description>
      </Alert.Root>
    {/if}

    <form
      onsubmit={(event) => {
        event.preventDefault();
        void submitMessage();
      }}
    >
      <InputGroup.Root class="h-auto min-h-20">
        <InputGroup.Textarea
          bind:value={draft}
          aria-label="Message chatbot"
          disabled={sending}
          onkeydown={handleComposerKeydown}
          placeholder="Ask the chatbot…"
          rows={2}
        />
        <InputGroup.Addon align="block-end" class="justify-end border-t">
          <span class="mr-auto text-xs text-muted-foreground"
            >Enter to send · Shift+Enter for a new line</span
          >
          <InputGroup.Button type="submit" size="sm" disabled={!draft.trim() || sending}>
            {#if sending}
              <Spinner data-icon="inline-start" />
              Sending
            {:else}
              <SendIcon data-icon="inline-start" />
              Send
            {/if}
          </InputGroup.Button>
        </InputGroup.Addon>
      </InputGroup.Root>
    </form>
  </div>
</section>
