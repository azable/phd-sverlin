<script lang="ts">
  import { enhance } from '$app/forms';

  import { actionFailureMessage } from '$lib/client/admin/action-result';
  import * as Alert from '$lib/client/components/ui/alert';
  import * as AlertDialog from '$lib/client/components/ui/alert-dialog';
  import { Button, buttonVariants } from '$lib/client/components/ui/button';
  import * as Field from '$lib/client/components/ui/field';
  import { Input } from '$lib/client/components/ui/input';
  import { Spinner } from '$lib/client/components/ui/spinner';

  import type { SubmitFunction } from '@sveltejs/kit';

  type Props = {
    participant: {
      id: string;
      participantId: string;
    };
  };

  let { participant }: Props = $props();
  let open = $state(false);
  let confirmation = $state('');
  let submitting = $state(false);
  let submissionError = $state<string>();
  const expectedConfirmation = $derived(`DELETE ${participant.participantId}`);

  const deleteParticipant: SubmitFunction = () => {
    submitting = true;
    submissionError = undefined;
    return async ({ result, update }) => {
      const failure = actionFailureMessage(result, 'Participant deletion failed.');
      try {
        await update();
        if (failure) submissionError = failure;
        else open = false;
      } finally {
        submitting = false;
      }
    };
  };

  function prepareConfirmation() {
    confirmation = '';
    submitting = false;
    submissionError = undefined;
  }
</script>

<AlertDialog.Root bind:open>
  <AlertDialog.Trigger
    class={buttonVariants({ variant: 'destructive' })}
    onclick={prepareConfirmation}
  >
    Delete participant
  </AlertDialog.Trigger>
  <AlertDialog.Content>
    <form method="POST" action="?/purgeParticipant" use:enhance={deleteParticipant}>
      <AlertDialog.Header>
        <AlertDialog.Title>Delete participant {participant.participantId}?</AlertDialog.Title>
        <AlertDialog.Description>
          This permanently deletes the participant account, projects, retained queue records, and
          private resources. Export first if the approved research protocol permits retaining this
          data.
        </AlertDialog.Description>
      </AlertDialog.Header>
      {#if submissionError}
        <Alert.Root variant="destructive" class="mt-4">
          <Alert.Title>Participant deletion failed</Alert.Title>
          <Alert.Description>{submissionError}</Alert.Description>
        </Alert.Root>
      {/if}
      <input type="hidden" name="id" value={participant.id} />
      <Field.FieldGroup class="py-4">
        <Field.Field>
          <Field.FieldLabel for={`purge-${participant.id}`}>
            Enter {expectedConfirmation} to confirm
          </Field.FieldLabel>
          <Input
            id={`purge-${participant.id}`}
            name="confirmation"
            required
            autocomplete="off"
            disabled={submitting}
            bind:value={confirmation}
          />
        </Field.Field>
      </Field.FieldGroup>
      <AlertDialog.Footer>
        <AlertDialog.Cancel disabled={submitting}>Cancel</AlertDialog.Cancel>
        <Button
          type="submit"
          variant="destructive"
          disabled={submitting || confirmation !== expectedConfirmation}
          aria-busy={submitting}
          aria-label={submitting ? 'Deleting participant' : undefined}
        >
          {#if submitting}
            <Spinner data-icon="inline-start" />Deleting…
          {:else}
            Delete participant
          {/if}
        </Button>
      </AlertDialog.Footer>
    </form>
  </AlertDialog.Content>
</AlertDialog.Root>
