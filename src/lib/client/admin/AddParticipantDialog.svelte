<script lang="ts">
  import { enhance } from '$app/forms';

  import { actionFailureMessage } from '$lib/client/admin/action-result';
  import * as Alert from '$lib/client/components/ui/alert';
  import { Button, buttonVariants } from '$lib/client/components/ui/button';
  import * as Dialog from '$lib/client/components/ui/dialog';
  import * as Field from '$lib/client/components/ui/field';
  import { Input } from '$lib/client/components/ui/input';

  import type { SubmitFunction } from '@sveltejs/kit';

  let open = $state(false);
  let participantId = $state('');
  let submissionError = $state<string>();

  const createParticipant: SubmitFunction = () => {
    submissionError = undefined;
    return async ({ result, update }) => {
      const failure = actionFailureMessage(result, 'Participant creation failed.');
      await update();
      if (failure) submissionError = failure;
      else open = false;
    };
  };

  function prepareParticipant() {
    participantId = '';
    submissionError = undefined;
  }
</script>

<Dialog.Root bind:open>
  <Dialog.Trigger class={buttonVariants()} onclick={prepareParticipant}
    >Add participant</Dialog.Trigger
  >
  <Dialog.Content>
    <form method="POST" action="?/create" use:enhance={createParticipant}>
      <Dialog.Header>
        <Dialog.Title>Add participant</Dialog.Title>
        <Dialog.Description>
          Create a participant account and generate its one-time credentials.
        </Dialog.Description>
      </Dialog.Header>
      {#if submissionError}
        <Alert.Root variant="destructive" class="mt-4">
          <Alert.Title>Participant creation failed</Alert.Title>
          <Alert.Description>{submissionError}</Alert.Description>
        </Alert.Root>
      {/if}
      <Field.FieldGroup class="py-4">
        <Field.Field>
          <Field.FieldLabel for="participant-id">Participant ID</Field.FieldLabel>
          <Input
            id="participant-id"
            name="participantId"
            required
            maxlength={128}
            autocomplete="off"
            bind:value={participantId}
          />
        </Field.Field>
      </Field.FieldGroup>
      <Dialog.Footer>
        <Dialog.Close class={buttonVariants({ variant: 'outline' })}>Cancel</Dialog.Close>
        <Button type="submit">Create participant</Button>
      </Dialog.Footer>
    </form>
  </Dialog.Content>
</Dialog.Root>
