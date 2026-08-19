<script lang="ts">
  import { onMount, tick } from 'svelte';

  import BotIcon from '@lucide/svelte/icons/bot';
  import RotateCcwIcon from '@lucide/svelte/icons/rotate-ccw';
  import SendIcon from '@lucide/svelte/icons/send';

  import * as Alert from '$lib/components/ui/alert';
  import { Button } from '$lib/components/ui/button';
  import * as InputGroup from '$lib/components/ui/input-group';
  import { ScrollArea } from '$lib/components/ui/scroll-area';
  import { Spinner } from '$lib/components/ui/spinner';
  import { ChatState } from './chat-state.svelte';

  const chat = new ChatState();
  let transcriptElement = $state<HTMLElement | null>(null);

  onMount(() => {
    void loadChat();
  });

  async function loadChat() {
    await chat.load();
    await scrollToLatest();
  }

  async function submitMessage() {
    await chat.submit();
    await scrollToLatest();
  }

  async function resetChat() {
    await chat.reset();
    await scrollToLatest();
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

<section class="flex min-h-0 flex-1 flex-col" aria-label="Chat with AI assistant">
  <ScrollArea bind:viewportRef={transcriptElement} class="min-h-0 flex-1 px-4 py-5">
    <div class="flex flex-col gap-4 pr-3" aria-live="polite" aria-label="Chat transcript">
      {#each chat.messages as message (message.id)}
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

      {#if chat.sending}
        <div class="flex items-center gap-2 text-sm text-muted-foreground" aria-live="polite">
          <Spinner />
          Thinking…
        </div>
      {/if}
    </div>
  </ScrollArea>

  <div class="flex flex-col gap-3 border-t bg-background p-4">
    {#if chat.error}
      <Alert.Root variant="destructive">
        <Alert.Title>Unable to send message</Alert.Title>
        <Alert.Description>{chat.error}</Alert.Description>
      </Alert.Root>
    {/if}

    <form
      onsubmit={(event) => {
        event.preventDefault();
        void submitMessage();
      }}
    >
      <div class="mb-2 flex justify-end">
        <Button
          type="button"
          variant="ghost"
          size="sm"
          disabled={chat.sending}
          onclick={() => void resetChat()}
        >
          <RotateCcwIcon data-icon="inline-start" />
          Reset chat
        </Button>
      </div>
      <InputGroup.Root class="h-auto min-h-20">
        <InputGroup.Textarea
          bind:value={chat.draft}
          aria-label="Message AI assistant"
          disabled={chat.sending}
          onkeydown={handleComposerKeydown}
          placeholder="Ask the AI assistant…"
          rows={2}
        />
        <InputGroup.Addon align="block-end" class="justify-end border-t">
          <span class="mr-auto text-xs text-muted-foreground"
            >Enter to send · Shift+Enter for a new line</span
          >
          <InputGroup.Button type="submit" size="sm" disabled={!chat.draft.trim() || chat.sending}>
            {#if chat.sending}
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
