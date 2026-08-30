<script lang="ts">
  import { enhance } from '$app/forms';

  import { actionFailureMessage } from '$lib/client/admin/action-result';
  import * as Alert from '$lib/client/components/ui/alert';
  import { Button, buttonVariants } from '$lib/client/components/ui/button';
  import * as Dialog from '$lib/client/components/ui/dialog';
  import * as Field from '$lib/client/components/ui/field';
  import { Input } from '$lib/client/components/ui/input';
  import { Spinner } from '$lib/client/components/ui/spinner';

  import type { SubmitFunction } from '@sveltejs/kit';

  type Props = {
    participant: {
      id: string;
      participantId: string;
      giftCardUrl?: string;
    };
    onSaved?: () => void | Promise<void>;
  };

  let { participant, onSaved }: Props = $props();
  let open = $state(false);
  let submitting = $state(false);
  let submissionError = $state<string>();
  const formId = $derived(`gift-card-form-${participant.id}`);

  const submitGiftCard: SubmitFunction = () => {
    submitting = true;
    submissionError = undefined;
    return async ({ result, update }) => {
      const failure = actionFailureMessage(result, 'Gift-card update failed.');
      try {
        await update();
        if (failure) submissionError = failure;
        else {
          await onSaved?.();
          open = false;
        }
      } finally {
        submitting = false;
      }
    };
  };

  function prepareGiftCard() {
    submitting = false;
    submissionError = undefined;
  }
</script>

<Dialog.Root bind:open>
  <Dialog.Trigger class={buttonVariants({ variant: 'outline' })} onclick={prepareGiftCard}>
    {participant.giftCardUrl ? 'Edit gift card' : 'Add gift card'}
  </Dialog.Trigger>
  <Dialog.Content>
    <form id={formId} method="POST" action="?/giftCard" use:enhance={submitGiftCard}>
      <Dialog.Header>
        <Dialog.Title>Gift card for {participant.participantId}</Dialog.Title>
        <Dialog.Description>
          This link is shown only to this participant after the study is complete.
        </Dialog.Description>
      </Dialog.Header>
      {#if submissionError}
        <Alert.Root variant="destructive" class="mt-4">
          <Alert.Title>Gift-card update failed</Alert.Title>
          <Alert.Description>{submissionError}</Alert.Description>
        </Alert.Root>
      {/if}
      <input type="hidden" name="id" value={participant.id} />
      <Field.FieldGroup class="py-4">
        <Field.Field>
          <Field.FieldLabel for={`gift-card-${participant.id}`}>Gift-card URL</Field.FieldLabel>
          <Input
            id={`gift-card-${participant.id}`}
            name="giftCardUrl"
            type="url"
            inputmode="url"
            maxlength={2048}
            placeholder="https://…"
            autocomplete="off"
            disabled={submitting}
            value={participant.giftCardUrl ?? ''}
          />
        </Field.Field>
      </Field.FieldGroup>
    </form>
    <Dialog.Footer>
      <Dialog.Close class={buttonVariants({ variant: 'outline' })} disabled={submitting}
        >Cancel</Dialog.Close
      >
      <Button
        type="submit"
        form={formId}
        disabled={submitting}
        aria-busy={submitting}
        aria-label={submitting ? 'Saving gift card' : undefined}
      >
        {#if submitting}<Spinner data-icon="inline-start" />Saving…{:else}Save gift card{/if}
      </Button>
    </Dialog.Footer>
  </Dialog.Content>
</Dialog.Root>
