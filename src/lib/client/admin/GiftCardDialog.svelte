<script lang="ts">
  import { enhance } from '$app/forms';

  import { actionFailureMessage } from '$lib/client/admin/action-result';
  import * as Alert from '$lib/client/components/ui/alert';
  import { buttonVariants } from '$lib/client/components/ui/button';
  import { Button } from '$lib/client/components/ui/button';
  import * as Dialog from '$lib/client/components/ui/dialog';
  import * as Field from '$lib/client/components/ui/field';
  import { Input } from '$lib/client/components/ui/input';

  import type { SubmitFunction } from '@sveltejs/kit';

  type Props = {
    participant: {
      id: string;
      participantId: string;
      giftCardUrl?: string;
    };
  };

  let { participant }: Props = $props();
  let open = $state(false);
  let submissionError = $state<string>();
  const formId = $derived(`gift-card-form-${participant.id}`);

  const submitGiftCard: SubmitFunction = () => {
    submissionError = undefined;
    return async ({ result, update }) => {
      const failure = actionFailureMessage(result, 'Gift-card update failed.');
      await update();
      if (failure) submissionError = failure;
      else open = false;
    };
  };

  function prepareGiftCard() {
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
            value={participant.giftCardUrl ?? ''}
          />
        </Field.Field>
      </Field.FieldGroup>
    </form>
    <Dialog.Footer>
      {#if participant.giftCardUrl}
        <form method="POST" action="?/giftCard" use:enhance={submitGiftCard}>
          <input type="hidden" name="id" value={participant.id} />
          <Button type="submit" name="clearGiftCard" value="true" variant="outline">Clear</Button>
        </form>
      {/if}
      <Button type="submit" form={formId}>Save gift card</Button>
    </Dialog.Footer>
  </Dialog.Content>
</Dialog.Root>
