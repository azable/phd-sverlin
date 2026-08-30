<script lang="ts">
  import { Badge } from '$lib/client/components/ui/badge';
  import { Button } from '$lib/client/components/ui/button';
  import type { MessageContent } from '$lib/shared/projects/events/message-content';

  import { renderSafeMarkdown } from './markdown';
  import {
    referenceChipLabel,
    singletonReferenceSegments,
    type ReferenceSegment
  } from './reference-labels';

  type Props = {
    content: MessageContent;
    interactive?: boolean;
    inverted?: boolean;
    onReferenceActivate?: (reference: ReferenceSegment, extend: boolean) => void;
  };

  let {
    content,
    interactive = true,
    inverted = false,
    onReferenceActivate = () => {}
  }: Props = $props();
</script>

<div class="message-content text-base">
  {#each content as segment, index (`${segment.type}-${index}`)}
    {#if segment.type === 'markdown'}
      <!-- renderSafeMarkdown applies the allowlist and URL policy before this HTML boundary. -->
      <!-- eslint-disable-next-line svelte/no-at-html-tags -->
      <span class="message-markdown">{@html renderSafeMarkdown(segment.text)}</span>
    {:else}
      {#each singletonReferenceSegments(segment) as reference (reference.type === 'presentation-ref' ? `presentation:${reference.presentationId}` : `element:${reference.presentationEvent}:${reference.step}:${reference.instances[0]}`)}
        {#if interactive}
          <Button
            type="button"
            size="xs"
            variant={inverted ? 'secondary' : 'outline'}
            class="mx-0.5 inline-flex align-baseline font-mono"
            onclick={(event) => onReferenceActivate(reference, event.shiftKey)}
          >
            {referenceChipLabel(reference)}
          </Button>
        {:else}
          <Badge
            variant={inverted ? 'secondary' : 'outline'}
            class="mx-0.5 inline-flex overflow-visible align-baseline font-mono"
          >
            {referenceChipLabel(reference)}
          </Badge>
        {/if}
      {/each}
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
