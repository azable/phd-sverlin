<script lang="ts">
  import { Button } from '$lib/client/components/ui/button';
  import { presentationDisplayId } from '$lib/client/visualization/presentation-history';
  import type {
    MessageContent,
    MessageContentSegment
  } from '$lib/shared/projects/events/message-content';

  import { renderSafeMarkdown } from './markdown';

  type ReferenceSegment = Exclude<MessageContentSegment, { type: 'markdown' }>;
  type Props = {
    content: MessageContent;
    onReferenceActivate?: (reference: ReferenceSegment, extend: boolean) => void;
  };

  let { content, onReferenceActivate = () => {} }: Props = $props();

  function referenceLabel(reference: ReferenceSegment): string {
    const label = presentationDisplayId(reference.presentationId);
    return reference.type === 'presentation-ref'
      ? label
      : `${reference.instances.length} element${reference.instances.length === 1 ? '' : 's'} · ${label} · Step ${reference.step + 1}`;
  }
</script>

<div class="message-content text-base">
  {#each content as segment, index (`${segment.type}-${index}`)}
    {#if segment.type === 'markdown'}
      <!-- renderSafeMarkdown applies the allowlist and URL policy before this HTML boundary. -->
      <!-- eslint-disable-next-line svelte/no-at-html-tags -->
      <span class="message-markdown">{@html renderSafeMarkdown(segment.text)}</span>
    {:else}
      <Button
        type="button"
        size="xs"
        variant="outline"
        class="mx-0.5 inline-flex align-baseline font-mono"
        onclick={(event) => onReferenceActivate(segment, event.shiftKey)}
      >
        {referenceLabel(segment)}
      </Button>
    {/if}
  {/each}
</div>

<style>
  .message-content :global(.message-markdown > p:first-child) {
    display: inline;
  }

  .message-content :global(.message-markdown > p + p),
  .message-content :global(.message-markdown > ul),
  .message-content :global(.message-markdown > ol),
  .message-content :global(.message-markdown > pre),
  .message-content :global(.message-markdown > blockquote) {
    margin-top: 0.5rem;
  }

  .message-content :global(ul),
  .message-content :global(ol) {
    padding-left: 1.25rem;
  }

  .message-content :global(ul) {
    list-style: disc;
  }

  .message-content :global(ol) {
    list-style: decimal;
  }

  .message-content :global(a) {
    text-decoration: underline;
    text-underline-offset: 0.15em;
  }

  .message-content :global(code) {
    font-family: var(--font-mono, ui-monospace, monospace);
  }
</style>
