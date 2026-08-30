<script lang="ts">
  import { enhance } from '$app/forms';

  import { actionFailureMessage } from '$lib/client/admin/action-result';
  import * as Alert from '$lib/client/components/ui/alert';
  import * as AlertDialog from '$lib/client/components/ui/alert-dialog';
  import { Button, buttonVariants } from '$lib/client/components/ui/button';

  import type { SubmitFunction } from '@sveltejs/kit';

  type Props = {
    participant: {
      id: string;
      participantId: string;
    };
  };

  let { participant }: Props = $props();
  let open = $state(false);
  let submissionError = $state<string>();

  const generatePassword: SubmitFunction = () => {
    submissionError = undefined;
    return async ({ result, update }) => {
      const failure = actionFailureMessage(result, 'Password reset failed.');
      await update();
      if (failure) submissionError = failure;
      else open = false;
    };
  };

  function preparePasswordReset() {
    submissionError = undefined;
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
    <form method="POST" action="?/password" use:enhance={generatePassword}>
      <AlertDialog.Header>
        <AlertDialog.Title
          >Generate a new password for {participant.participantId}?</AlertDialog.Title
        >
        <AlertDialog.Description>
          The current password will stop working and existing participant sessions will be revoked.
          The new password is shown only once.
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
        <AlertDialog.Cancel>Cancel</AlertDialog.Cancel>
        <Button type="submit">Generate new password</Button>
      </AlertDialog.Footer>
    </form>
  </AlertDialog.Content>
</AlertDialog.Root>
