<script lang="ts">
  import SendIcon from '@lucide/svelte/icons/send';
  import XIcon from '@lucide/svelte/icons/x';

  import { Badge } from '$lib/client/components/ui/badge';
  import * as Field from '$lib/client/components/ui/field';
  import * as InputGroup from '$lib/client/components/ui/input-group';
  import { Spinner } from '$lib/client/components/ui/spinner';
  import type { ProjectSession } from '$lib/client/projects/project-session.svelte';
  import type { VisualSelection } from '$lib/shared/projects/events/values';

  /** Public properties for composing project feedback. */
  type Props = {
    session: ProjectSession;
    seed: number;
    selection?: VisualSelection;
  };

  let { session, seed, selection }: Props = $props();

  let text = $state('');
  let judgement = $state<VisualSelection['judgement']>('neutral');

  async function submit(event: SubmitEvent) {
    event.preventDefault();
    if (!session.atHead || session.pending) return;
    const message = text.trim();
    if (!message && session.focusedEvents.length === 0 && !selection) return;
    const succeeded = await session.runCommand({
      type: 'feedback',
      text: message || undefined,
      focus: session.focusedEvents,
      selection: selection ? { ...selection, judgement } : undefined,
      seed
    });
    if (succeeded) {
      text = '';
      session.focusedEvents = [];
      judgement = 'neutral';
    }
  }
</script>

<form class="border-t bg-background p-4" onsubmit={submit}>
  <Field.FieldGroup>
    <Field.Field>
      {#if session.focusedEvents.length > 0 || selection}
        <div class="flex flex-wrap gap-2">
          {#each session.focusedEvents as id (id)}
            <Badge variant="secondary">
              Event #{id}
              <button
                type="button"
                aria-label={`Remove event ${id}`}
                onclick={() => session.removeFocus(id)}
              >
                <XIcon class="size-3" />
              </button>
            </Badge>
          {/each}
          {#if selection}
            <Badge variant="outline">{selection.instances.length} selected element(s)</Badge>
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
          bind:value={text}
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
              (!text.trim() && !selection && session.focusedEvents.length === 0)}
          >
            {#if session.pending?.type === 'feedback'}
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
