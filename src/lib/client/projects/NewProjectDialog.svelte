<script lang="ts">
  import FilePlusIcon from '@lucide/svelte/icons/file-plus-2';

  import { Badge } from '$lib/client/components/ui/badge';
  import { Button } from '$lib/client/components/ui/button';
  import * as Dialog from '$lib/client/components/ui/dialog';
  import * as Field from '$lib/client/components/ui/field';
  import { ScrollArea } from '$lib/client/components/ui/scroll-area';
  import { Spinner } from '$lib/client/components/ui/spinner';
  import * as ToggleGroup from '$lib/client/components/ui/toggle-group';
  import type { ProjectTemplateSummary } from '$lib/shared/projects/creation';

  import type { ProjectSession } from './project-session.svelte';

  type Props = {
    session: ProjectSession;
    templates: ProjectTemplateSummary[];
    devMode: boolean;
    disabled?: boolean;
  };

  let { session, templates, devMode, disabled = false }: Props = $props();
  let open = $state(false);
  let selectedTemplateId = $state('blank');

  const selectedTemplate = $derived(templates.find(({ id }) => id === selectedTemplateId));

  function selectTemplate(value: string | string[]) {
    if (typeof value === 'string' && value) selectedTemplateId = value;
  }

  async function create(event: SubmitEvent) {
    event.preventDefault();
    if (!selectedTemplate) return;
    await session.createProject({ templateId: selectedTemplate.id }, devMode);
  }
</script>

<Dialog.Root bind:open>
  <Dialog.Trigger>
    {#snippet child({ props })}
      <Button {...props} type="button" size="sm" variant="ghost" {disabled}>
        <FilePlusIcon data-icon="inline-start" />New project
      </Button>
    {/snippet}
  </Dialog.Trigger>

  <Dialog.Content class="sm:max-w-2xl" showCloseButton={!session.creating}>
    <Dialog.Header>
      <Dialog.Title>Create a project</Dialog.Title>
      <Dialog.Description>
        Choose a starting template. The source is copied into a new independent project.
      </Dialog.Description>
    </Dialog.Header>

    <form class="flex min-h-0 min-w-0 flex-col gap-4" onsubmit={create}>
      <Field.FieldSet class="min-w-0" disabled={session.creating}>
        <Field.FieldLegend>Starting template</Field.FieldLegend>
        <Field.FieldDescription>
          Templates only determine the initial source; they do not restrict later editing.
        </Field.FieldDescription>

        <ScrollArea class="h-[min(50vh,30rem)] min-w-0 pr-3">
          <ToggleGroup.Root
            value={selectedTemplateId}
            onValueChange={selectTemplate}
            type="single"
            orientation="vertical"
            variant="outline"
            spacing={2}
            class="w-full min-w-0 flex-col items-stretch overflow-hidden"
            aria-label="Starting template"
          >
            {#each templates as template (template.id)}
              <ToggleGroup.Item
                value={template.id}
                aria-label={`Use ${template.title}`}
                class="h-auto max-w-full min-w-0 flex-col items-start overflow-hidden p-3 text-left whitespace-normal"
              >
                <span class="w-full min-w-0 font-medium">{template.title}</span>
                <span class="w-full min-w-0 text-sm font-normal text-muted-foreground">
                  {template.summary}
                </span>
                <span class="flex w-full min-w-0 flex-wrap gap-1 pt-1">
                  {#each template.features as feature (feature)}
                    <Badge variant="outline">{feature}</Badge>
                  {/each}
                </span>
              </ToggleGroup.Item>
            {/each}
          </ToggleGroup.Root>
        </ScrollArea>
      </Field.FieldSet>

      <Dialog.Footer>
        <Dialog.Close disabled={session.creating}>
          {#snippet child({ props })}
            <Button {...props} type="button" variant="outline" disabled={session.creating}>
              Cancel
            </Button>
          {/snippet}
        </Dialog.Close>
        <Button type="submit" disabled={!selectedTemplate || session.creating}>
          {#if session.creating}
            <Spinner data-icon="inline-start" />Creating project
          {:else}
            Create from {selectedTemplate?.title ?? 'template'}
          {/if}
        </Button>
      </Dialog.Footer>
    </form>
  </Dialog.Content>
</Dialog.Root>
