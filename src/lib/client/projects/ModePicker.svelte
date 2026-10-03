<script lang="ts">
  import CheckIcon from '@lucide/svelte/icons/check';

  import * as Field from '$lib/client/components/ui/field';
  import * as ToggleGroup from '$lib/client/components/ui/toggle-group';
  import type { VisualizationMode } from '$lib/shared/presentations';
  import { modeCatalog } from '$lib/modes/catalog';

  type Props = { value: VisualizationMode; disabled?: boolean };
  let { value = $bindable(), disabled = false }: Props = $props();
  const modes = Object.entries(modeCatalog) as Array<
    [VisualizationMode, (typeof modeCatalog)[VisualizationMode]]
  >;

  function selectMode(next: string | string[]) {
    if (typeof next === 'string' && next in modeCatalog) value = next as VisualizationMode;
  }
</script>

<Field.FieldSet {disabled}>
  <Field.FieldLegend>Visualization mode</Field.FieldLegend>
  <ToggleGroup.Root
    bind:value={() => value, selectMode}
    {disabled}
    type="single"
    variant="outline"
    spacing={2}
    aria-label="Visualization mode"
  >
    {#each modes as [id, mode] (id)}
      <ToggleGroup.Item value={id} aria-label={`Use ${mode.title}`}>
        {#if value === id}
          <CheckIcon data-icon="inline-start" />
        {/if}
        {mode.title}
      </ToggleGroup.Item>
    {/each}
  </ToggleGroup.Root>
</Field.FieldSet>
