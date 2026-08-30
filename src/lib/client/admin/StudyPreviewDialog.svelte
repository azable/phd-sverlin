<script lang="ts">
  import { enhance } from '$app/forms';

  import { actionFailureMessage } from '$lib/client/admin/action-result';
  import * as Alert from '$lib/client/components/ui/alert';
  import { Button, buttonVariants } from '$lib/client/components/ui/button';
  import * as Dialog from '$lib/client/components/ui/dialog';
  import * as Field from '$lib/client/components/ui/field';
  import { Spinner } from '$lib/client/components/ui/spinner';
  import * as ToggleGroup from '$lib/client/components/ui/toggle-group';
  import type { StudyDefinition } from '$lib/shared/study/definition';

  import type { SubmitFunction } from '@sveltejs/kit';

  type Props = { definition: StudyDefinition };
  let { definition }: Props = $props();
  let open = $state(false);
  let armId = $state('');
  let mode = $state<'full' | 'phase'>('full');
  let phaseId = $state('');
  let preparing = $state(false);
  let submissionError = $state<string>();

  function initializePreview() {
    armId = definition.assignment.tieBreakOrder[0] ?? '';
    phaseId = definition.flow[0]?.id ?? '';
    mode = 'full';
    preparing = false;
    submissionError = undefined;
  }

  function selectArm(value: string | string[]) {
    if (typeof value === 'string' && value) armId = value;
  }

  function selectMode(value: string | string[]) {
    if (value === 'full' || value === 'phase') mode = value;
  }

  const preparePreview: SubmitFunction = () => {
    preparing = true;
    submissionError = undefined;
    return async ({ result, update }) => {
      const failure = actionFailureMessage(result, 'Study preview creation failed.');
      try {
        await update();
        if (failure) submissionError = failure;
      } finally {
        preparing = false;
      }
    };
  };
</script>

<Dialog.Root bind:open>
  <Dialog.Trigger class={buttonVariants({ variant: 'outline' })} onclick={initializePreview}>
    Create preview
  </Dialog.Trigger>
  <Dialog.Content showCloseButton={!preparing}>
    <form method="POST" action="?/createPreview" use:enhance={preparePreview}>
      <Dialog.Header>
        <Dialog.Title>Preview {definition.name} v{definition.version}</Dialog.Title>
        <Dialog.Description>
          Preview the complete configured flow or exercise one isolated phase.
        </Dialog.Description>
      </Dialog.Header>
      {#if submissionError}
        <Alert.Root variant="destructive" class="mt-4">
          <Alert.Title>Preview creation failed</Alert.Title>
          <Alert.Description>{submissionError}</Alert.Description>
        </Alert.Root>
      {/if}
      <Field.FieldGroup class="py-4">
        <Field.FieldSet disabled={preparing}>
          <Field.FieldLegend>Counterbalance arm</Field.FieldLegend>
          <ToggleGroup.Root
            type="single"
            value={armId}
            onValueChange={selectArm}
            variant="outline"
            aria-label="Preview arm"
          >
            {#each definition.assignment.tieBreakOrder as arm (arm)}
              <ToggleGroup.Item value={arm}>{arm}</ToggleGroup.Item>
            {/each}
          </ToggleGroup.Root>
        </Field.FieldSet>
        <Field.FieldSet disabled={preparing}>
          <Field.FieldLegend>Preview scope</Field.FieldLegend>
          <ToggleGroup.Root
            type="single"
            value={mode}
            onValueChange={selectMode}
            variant="outline"
            aria-label="Preview scope"
          >
            <ToggleGroup.Item value="full">Full flow</ToggleGroup.Item>
            <ToggleGroup.Item value="phase">One phase</ToggleGroup.Item>
          </ToggleGroup.Root>
        </Field.FieldSet>
        {#if mode === 'phase'}
          <Field.Field>
            <Field.FieldLabel for={`preview-phase-${definition.id}-${definition.version}`}>
              Phase
            </Field.FieldLabel>
            <select
              id={`preview-phase-${definition.id}-${definition.version}`}
              class="h-9 rounded-md border bg-background px-3 text-sm"
              disabled={preparing}
              bind:value={phaseId}
            >
              {#each definition.flow as phase (phase.id)}
                <option value={phase.id}>
                  {phase.kind === 'task' ? phase.instructions.title : phase.title}
                </option>
              {/each}
            </select>
          </Field.Field>
        {/if}
        <input type="hidden" name="studyId" value={definition.id} />
        <input type="hidden" name="studyVersion" value={definition.version} />
        <input type="hidden" name="armId" value={armId} />
        <input type="hidden" name="phaseId" value={mode === 'phase' ? phaseId : ''} />
      </Field.FieldGroup>
      <Dialog.Footer>
        <Dialog.Close class={buttonVariants({ variant: 'outline' })} disabled={preparing}
          >Cancel</Dialog.Close
        >
        <Button
          type="submit"
          disabled={preparing || !armId || (mode === 'phase' && !phaseId)}
          aria-busy={preparing}
          aria-label={preparing ? 'Creating preview' : undefined}
        >
          {#if preparing}<Spinner data-icon="inline-start" />Creating…{:else}Create preview{/if}
        </Button>
      </Dialog.Footer>
    </form>
  </Dialog.Content>
</Dialog.Root>
