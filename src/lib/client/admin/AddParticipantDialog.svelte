<script lang="ts">
  import { enhance } from '$app/forms';

  import {
    actionFailureMessage,
    participantCredentials,
    type ParticipantCredentials
  } from '$lib/client/admin/action-result';
  import * as Alert from '$lib/client/components/ui/alert';
  import { Button, buttonVariants } from '$lib/client/components/ui/button';
  import * as Dialog from '$lib/client/components/ui/dialog';
  import * as Field from '$lib/client/components/ui/field';
  import { Input } from '$lib/client/components/ui/input';
  import { Spinner } from '$lib/client/components/ui/spinner';
  import type { StudyDefinition } from '$lib/shared/study/definition';

  import type { SubmitFunction } from '@sveltejs/kit';

  type Props = {
    studies: Array<{ definition: StudyDefinition; enrollment: 'open' | 'closed' }>;
  };

  let { studies }: Props = $props();
  const openStudies = $derived(studies.filter(({ enrollment }) => enrollment === 'open'));
  let open = $state(false);
  let participantId = $state('');
  let studyKey = $state('');
  let submitting = $state(false);
  let submissionError = $state<string>();
  let credentials = $state.raw<ParticipantCredentials>();

  const createParticipant: SubmitFunction = () => {
    submitting = true;
    submissionError = undefined;
    return async ({ result, update }) => {
      const failure = actionFailureMessage(result, 'Participant creation failed.');
      const returnedCredentials = participantCredentials(result);
      try {
        await update();
        if (failure) submissionError = failure;
        else if (returnedCredentials) credentials = returnedCredentials;
        else submissionError = 'Participant creation did not return one-time credentials.';
      } finally {
        submitting = false;
      }
    };
  };

  function prepareParticipant() {
    participantId = '';
    studyKey = openStudies[0]
      ? `${openStudies[0].definition.id}@${openStudies[0].definition.version}`
      : '';
    submitting = false;
    submissionError = undefined;
    credentials = undefined;
  }

  const selectedStudy = $derived(
    openStudies.find(({ definition }) => `${definition.id}@${definition.version}` === studyKey)
      ?.definition
  );
</script>

<Dialog.Root bind:open>
  <Dialog.Trigger class={buttonVariants()} onclick={prepareParticipant}
    >Add participant</Dialog.Trigger
  >
  <Dialog.Content showCloseButton={!submitting}>
    {#if credentials}
      <Dialog.Header>
        <Dialog.Title>Participant created</Dialog.Title>
        <Dialog.Description>
          Copy this password now. It is shown once and cannot be recovered.
        </Dialog.Description>
      </Dialog.Header>
      <Field.FieldGroup class="py-4">
        <Field.Field>
          <Field.FieldLabel for="created-participant-id">Participant ID</Field.FieldLabel>
          <Input id="created-participant-id" readonly value={credentials.participantId} />
        </Field.Field>
        <Field.Field>
          <Field.FieldLabel for="created-participant-password">One-time password</Field.FieldLabel>
          <Input
            id="created-participant-password"
            class="font-mono"
            readonly
            value={credentials.password}
          />
        </Field.Field>
      </Field.FieldGroup>
      <Dialog.Footer>
        <Dialog.Close class={buttonVariants()}>Done</Dialog.Close>
      </Dialog.Footer>
    {:else}
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
              disabled={submitting}
              bind:value={participantId}
            />
          </Field.Field>
          <Field.Field>
            <Field.FieldLabel for="participant-study">Study version</Field.FieldLabel>
            <select
              id="participant-study"
              class="h-9 rounded-md border bg-background px-3 text-sm"
              required
              disabled={submitting}
              bind:value={studyKey}
            >
              {#each openStudies as study (`${study.definition.id}@${study.definition.version}`)}
                <option value={`${study.definition.id}@${study.definition.version}`}>
                  {study.definition.name} · v{study.definition.version}
                </option>
              {/each}
            </select>
            <Field.FieldDescription>
              The assignment cannot be changed after creation.
            </Field.FieldDescription>
          </Field.Field>
          <input type="hidden" name="studyId" value={selectedStudy?.id ?? ''} />
          <input type="hidden" name="studyVersion" value={selectedStudy?.version ?? ''} />
        </Field.FieldGroup>
        <Dialog.Footer>
          <Dialog.Close class={buttonVariants({ variant: 'outline' })} disabled={submitting}
            >Cancel</Dialog.Close
          >
          <Button
            type="submit"
            disabled={submitting || !selectedStudy}
            aria-busy={submitting}
            aria-label={submitting ? 'Creating participant' : undefined}
          >
            {#if submitting}
              <Spinner data-icon="inline-start" />Creating…
            {:else}
              Create participant
            {/if}
          </Button>
        </Dialog.Footer>
      </form>
    {/if}
  </Dialog.Content>
</Dialog.Root>
