<script lang="ts">
  import SendIcon from '@lucide/svelte/icons/send';
  import XIcon from '@lucide/svelte/icons/x';

  import { Badge } from '$lib/components/ui/badge';
  import * as Field from '$lib/components/ui/field';
  import * as InputGroup from '$lib/components/ui/input-group';
  import { Spinner } from '$lib/components/ui/spinner';
  import type { VisualSelectionAttachment } from '$lib/projects/types';
  import type { ProjectSession } from '$lib/projects/project-session.svelte';

  let {
    session,
    seed,
    selection
  }: {
    session: ProjectSession;
    seed: number;
    selection?: VisualSelectionAttachment;
  } = $props();

  let judgement = $state<VisualSelectionAttachment['judgement']>('neutral');

  async function submit(event: SubmitEvent) {
    event.preventDefault();
    if (!session.atHead || session.pending) return;
    const text = session.feedbackDraft.trim();
    const attachments = [
      ...session.attachments,
      ...(selection ? [{ ...selection, judgement }] : [])
    ];
    if (!text && attachments.length === 0) return;
    const succeeded = await session.runAction('feedback', {
      text,
      attachments: JSON.stringify(attachments),
      seed: String(seed)
    });
    if (succeeded) {
      session.feedbackDraft = '';
      session.attachments = [];
      judgement = 'neutral';
    }
  }
</script>

<form class="border-t bg-background p-4" onsubmit={submit}>
  <Field.FieldGroup>
    <Field.Field>
      {#if session.attachments.length > 0 || selection}
        <div class="flex flex-wrap gap-2">
          {#each session.attachments as attachment, index (index)}
            <Badge variant="secondary">
              {attachment.kind === 'timeline-reference'
                ? `${attachment.eventIds.length} Timeline reference(s)`
                : `${attachment.elements.length} selected element(s)`}
              <button
                type="button"
                aria-label="Remove attachment"
                onclick={() => session.removeAttachment(index)}
              >
                <XIcon class="size-3" />
              </button>
            </Badge>
          {/each}
          {#if selection}
            <Badge variant="outline">{selection.elements.length} selected element(s)</Badge>
            <label class="flex items-center gap-2 text-xs text-muted-foreground">
              Mark as
              <select
                bind:value={judgement}
                class="h-7 rounded-md border bg-background px-2 text-foreground"
                disabled={!session.atHead || !!session.pending}
                aria-label="Selected element judgement"
              >
                <option value="neutral">Reference</option>
                <option value="preferred">Preferred</option>
                <option value="undesired">Undesired</option>
              </select>
            </label>
          {/if}
        </div>
      {/if}
      <InputGroup.Root class="h-auto min-h-20">
        <InputGroup.Textarea
          bind:value={session.feedbackDraft}
          aria-label="Project feedback"
          placeholder="Comment on the project or selected elements…"
          disabled={!session.atHead || !!session.pending}
          rows={2}
        />
        <InputGroup.Addon align="block-end" class="justify-end border-t">
          <span class="mr-auto text-xs text-muted-foreground">
            {session.atHead
              ? 'Feedback becomes an immutable event'
              : 'Return to present to respond'}
          </span>
          <InputGroup.Button
            type="submit"
            size="sm"
            disabled={!session.atHead ||
              !!session.pending ||
              (!session.feedbackDraft.trim() && !selection && session.attachments.length === 0)}
          >
            {#if session.pending?.action === 'feedback'}
              <Spinner data-icon="inline-start" />Thinking
            {:else}
              <SendIcon data-icon="inline-start" />Submit
            {/if}
          </InputGroup.Button>
        </InputGroup.Addon>
      </InputGroup.Root>
    </Field.Field>
  </Field.FieldGroup>
</form>
