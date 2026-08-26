<script lang="ts">
  import { tick } from 'svelte';

  import EditIcon from '@lucide/svelte/icons/edit-3';
  import SaveIcon from '@lucide/svelte/icons/save';
  import XIcon from '@lucide/svelte/icons/x';

  import CodeMirrorEditor from '$lib/client/artifacts/CodeMirrorEditor.svelte';
  import * as AlertDialog from '$lib/client/components/ui/alert-dialog';
  import { Badge } from '$lib/client/components/ui/badge';
  import { Button } from '$lib/client/components/ui/button';
  import { Spinner } from '$lib/client/components/ui/spinner';

  import type { ProjectSession } from './project-session.svelte';

  /** Editing modes exposed to the parent project workspace. */
  export type ProjectArtifactEditMode = 'readonly' | 'editing';

  /** Public properties for the source artifact panel. */
  type Props = {
    session: ProjectSession;
    seed: number;
    editMode?: ProjectArtifactEditMode;
  };

  let {
    session,
    seed,
    editMode = $bindable<ProjectArtifactEditMode>('readonly')
  }: Props = $props();

  let draft = $state('');
  let discardRequested = $state(false);
  let editor = $state<{ focus: () => void } | null>(null);

  const artifact = $derived(session.snapshot.artifacts[session.snapshot.entryArtifactId]);
  const displayedSource = $derived(editMode === 'editing' ? draft : (artifact?.content.text ?? ''));
  const dirty = $derived(
    editMode === 'editing' && artifact !== undefined && draft !== artifact.content.text
  );

  function startEditing() {
    if (!artifact || !session.atHead || session.pending || session.maintenanceLocked) return;
    draft = artifact.content.text;
    editMode = 'editing';
    void tick().then(() => editor?.focus());
  }

  function cancelEditing() {
    if (dirty) {
      discardRequested = true;
      return;
    }
    editMode = 'readonly';
  }

  function discardDraft() {
    if (artifact) draft = artifact.content.text;
    discardRequested = false;
    editMode = 'readonly';
  }

  async function saveDraft() {
    if (!artifact || !dirty || session.pending || !session.atHead || session.maintenanceLocked)
      return;
    const succeeded = await session.runCommand({
      type: 'save',
      artifactId: artifact.artifactId,
      source: draft,
      seed
    });
    if (succeeded) {
      editMode = 'readonly';
    }
  }

  function updateDraft(source: string) {
    draft = source;
  }
</script>

<section class="flex h-full min-h-0 flex-col p-3" aria-label="Project artifact">
  {#if artifact}
    <div class="flex min-h-0 flex-1 flex-col overflow-hidden rounded-xl border bg-card">
      <header class="flex flex-wrap items-center gap-2 border-b px-4 py-3">
        <EditIcon class="size-4 shrink-0 text-muted-foreground" />
        <div class="mr-auto min-w-0">
          <p class="truncate font-mono text-xs">{artifact.path}</p>
          <p class="text-xs text-muted-foreground">
            {session.atHead ? 'Current artifact' : `Artifact at event #${session.snapshot.at}`}
          </p>
        </div>
        <Badge variant="outline">{artifact.content.sha256.slice(0, 8)}</Badge>
        {#if editMode === 'readonly'}
          <Button
            size="sm"
            variant="outline"
            onclick={startEditing}
            disabled={!session.atHead || !!session.pending || session.maintenanceLocked}
          >
            <EditIcon data-icon="inline-start" />Edit
          </Button>
        {:else}
          <Badge variant="secondary">Editing · workspace locked</Badge>
          <Button size="sm" variant="ghost" onclick={cancelEditing} disabled={!!session.pending}>
            <XIcon data-icon="inline-start" />Cancel
          </Button>
          <Button
            size="sm"
            onclick={saveDraft}
            disabled={!dirty || !!session.pending || session.maintenanceLocked}
          >
            {#if session.pending?.type === 'save'}
              <Spinner data-icon="inline-start" />Compiling
            {:else}
              <SaveIcon data-icon="inline-start" />Save & render
            {/if}
          </Button>
        {/if}
      </header>

      {#if !session.atHead}
        <p class="border-b bg-muted px-4 py-2 text-xs text-muted-foreground">
          Historical source is read-only. Restore this event from the Timeline to make a new current
          version.
        </p>
      {/if}

      <div class="min-h-0 flex-1 overflow-hidden">
        <CodeMirrorEditor
          bind:this={editor}
          value={displayedSource}
          editable={editMode === 'editing' &&
            session.atHead &&
            !session.pending &&
            !session.maintenanceLocked}
          ariaLabel="Sverlin project source"
          onChange={updateDraft}
        />
      </div>
    </div>
  {:else}
    <div class="flex h-full items-center justify-center text-sm text-muted-foreground">
      This project state has no entry artifact.
    </div>
  {/if}

  <AlertDialog.Root bind:open={discardRequested}>
    <AlertDialog.Content>
      <AlertDialog.Header>
        <AlertDialog.Title>Discard unsaved changes?</AlertDialog.Title>
        <AlertDialog.Description>
          The draft has not entered the project Timeline and will be lost.
        </AlertDialog.Description>
      </AlertDialog.Header>
      <AlertDialog.Footer>
        <AlertDialog.Cancel>Keep editing</AlertDialog.Cancel>
        <AlertDialog.Action variant="destructive" onclick={discardDraft}>Discard</AlertDialog.Action
        >
      </AlertDialog.Footer>
    </AlertDialog.Content>
  </AlertDialog.Root>
</section>
