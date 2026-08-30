<script lang="ts">
  import { enhance } from '$app/forms';

  import {
    actionFailureMessage,
    participantCredentials,
    type ParticipantCredentials
  } from '$lib/client/admin/action-result';
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
  let submitting = $state(false);
  let submissionError = $state<string>();
  let credentials = $state.raw<ParticipantCredentials>();

  const generatePassword: SubmitFunction = () => {
    submitting = true;
    submissionError = undefined;
    return async ({ result, update }) => {
      const failure = actionFailureMessage(result, 'Password reset failed.');
      const returnedCredentials = participantCredentials(result);
      try {
        await update();
        if (failure) submissionError = failure;
        else if (returnedCredentials) credentials = returnedCredentials;
        else submissionError = 'Password reset did not return one-time credentials.';
      } finally {
        submitting = false;
      }
    };
  };

  function preparePasswordReset() {
    submitting = false;
    submissionError = undefined;
    credentials = undefined;
  }
</script>

<AlertDialog.Root bind:open>
  <AlertDialog.Trigger
    class={buttonVariants({ variant: 'outline' })}
    onclick={preparePasswordReset}
  >
    Generate new password
  </AlertDialog.Trigger>
  <AlertDialog.Content>
    {#if credentials}
      <AlertDialog.Header>
        <AlertDialog.Title>New password for {credentials.participantId}</AlertDialog.Title>
        <AlertDialog.Description>
          Copy this password now. It is shown once and cannot be recovered.
        </AlertDialog.Description>
      </AlertDialog.Header>
      <Field.FieldGroup class="py-4">
        <Field.Field>
          <Field.FieldLabel for={`new-password-${participant.id}`}
            >One-time password</Field.FieldLabel
          >
          <Input
            id={`new-password-${participant.id}`}
            class="font-mono"
            readonly
            value={credentials.password}
          />
        </Field.Field>
      </Field.FieldGroup>
      <AlertDialog.Footer class="mt-4">
        <AlertDialog.Cancel variant="default">Done</AlertDialog.Cancel>
      </AlertDialog.Footer>
    {:else}
      <form method="POST" action="?/password" use:enhance={generatePassword}>
        <AlertDialog.Header>
          <AlertDialog.Title>
            Generate a new password for {participant.participantId}?
          </AlertDialog.Title>
          <AlertDialog.Description>
            The current password will stop working and existing participant sessions will be
            revoked. The new password is shown only once.
          </AlertDialog.Description>
        </AlertDialog.Header>
        {#if submissionError}
          <Alert.Root variant="destructive" class="mt-4">
            <Alert.Title>Password reset failed</Alert.Title>
            <Alert.Description>{submissionError}</Alert.Description>
          </Alert.Root>
        {/if}
        <input type="hidden" name="id" value={participant.id} />
        <AlertDialog.Footer class="mt-4">
          <AlertDialog.Cancel disabled={submitting}>Cancel</AlertDialog.Cancel>
          <Button
            type="submit"
            disabled={submitting}
            aria-busy={submitting}
            aria-label={submitting ? 'Generating new password' : undefined}
          >
            {#if submitting}
              <Spinner data-icon="inline-start" />Generating…
            {:else}
              Generate new password
            {/if}
          </Button>
        </AlertDialog.Footer>
      </form>
    {/if}
  </AlertDialog.Content>
</AlertDialog.Root>
