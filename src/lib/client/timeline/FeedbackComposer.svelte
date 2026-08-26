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

  async function submit(event: SubmitEvent) {
    event.preventDefault();
    if (!session.atHead || session.pending || session.maintenanceLocked) return;
    const message = text.trim();
    if (!message && session.focusedEvents.length === 0 && !selection) return;
    const succeeded = await session.runCommand({
      type: 'feedback',
      text: message || undefined,
      focus: session.focusedEvents,
      selection,
      seed
    });
    if (succeeded) {
      text = '';
      session.focusedEvents = [];
    }
  }

  function submitOnEnter(event: KeyboardEvent) {
    if (event.key !== 'Enter' || event.shiftKey || event.isComposing) return;
    event.preventDefault();
    (event.currentTarget as HTMLTextAreaElement).form?.requestSubmit();
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
          {/if}
        </div>
      {/if}
      <InputGroup.Root class="h-auto min-h-20">
        <InputGroup.Textarea
          bind:value={text}
          aria-label="Project feedback"
          placeholder="Comment on the project or selected elements…"
          disabled={!session.atHead || !!session.pending || session.maintenanceLocked}
          rows={2}
          onkeydown={submitOnEnter}
        />
        <InputGroup.Addon align="block-end" class="justify-end border-t">
          <span class="mr-auto text-xs text-muted-foreground">
            {session.maintenanceLocked
              ? 'Read-only during maintenance'
              : session.atHead
                ? 'Enter submits · Shift+Enter adds a line'
                : 'Return to present to respond'}
          </span>
          <InputGroup.Button
            type="submit"
            size="sm"
            disabled={!session.atHead ||
              !!session.pending ||
              session.maintenanceLocked ||
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
