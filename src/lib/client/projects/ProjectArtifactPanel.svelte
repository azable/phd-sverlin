<script lang="ts">
  import { tick } from 'svelte';

  import EditIcon from '@lucide/svelte/icons/edit-3';
  import SaveIcon from '@lucide/svelte/icons/save';
  import XIcon from '@lucide/svelte/icons/x';
  import ChevronDownIcon from '@lucide/svelte/icons/chevron-down';

  import CodeMirrorEditor from '$lib/client/artifacts/CodeMirrorEditor.svelte';
  import * as AlertDialog from '$lib/client/components/ui/alert-dialog';
  import { Badge } from '$lib/client/components/ui/badge';
  import { Button } from '$lib/client/components/ui/button';
  import { Spinner } from '$lib/client/components/ui/spinner';
  import type { HtmlFramesManifest } from '$lib/shared/presentations';

  import type { ProjectSession } from './project-session.svelte';

  /** Editing modes exposed to the parent project workspace. */
  export type ProjectArtifactEditMode = 'readonly' | 'editing';

  /** Public properties for the source artifact panel. */
  type Props = {
    session: ProjectSession;
    presentationCount: 1 | 2;
    editMode?: ProjectArtifactEditMode;
  };

  let {
    session,
    presentationCount,
    editMode = $bindable<ProjectArtifactEditMode>('readonly')
  }: Props = $props();

  let draft = $state('');
  let discardRequested = $state(false);
  let expanded = $state(false);
  let editor = $state<{ focus: () => void } | null>(null);

  const artifact = $derived(session.snapshot.artifacts[session.snapshot.entryArtifactId]);
  const displayedSource = $derived(editMode === 'editing' ? draft : (artifact?.content.text ?? ''));
  const dirty = $derived(
    editMode === 'editing' && artifact !== undefined && draft !== artifact.content.text
  );

  function startEditing() {
    if (!artifact || !session.atHead || session.pending || session.readOnly) return;
    draft = artifact.content.text;
    expanded = true;
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
    if (!artifact || !dirty || session.pending || !session.atHead || session.readOnly) return;
    let succeeded = false;
    if (session.snapshot.renderer === 'html') {
      try {
        succeeded = await session.runCommand({
          type: 'save-html',
          artifactId: artifact.artifactId,
          manifest: JSON.parse(draft) as HtmlFramesManifest
        });
      } catch {
        session.error = 'The HTML artifact must be a valid frames manifest.';
      }
    } else {
      succeeded = await session.runCommand({
        type: 'save',
        artifactId: artifact.artifactId,
        source: draft,
        presentationCount
      });
    }
    if (succeeded) {
      editMode = 'readonly';
    }
  }

  function updateDraft(source: string) {
    draft = source;
  }
</script>

<section class="flex max-h-[38vh] min-h-0 flex-col border-t p-2" aria-label="Project artifact">
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
        <Button
          size="icon-sm"
          variant="ghost"
          onclick={() => (expanded = !expanded)}
          aria-label={expanded ? 'Collapse source' : 'Expand source'}
          aria-expanded={expanded}
        >
          <ChevronDownIcon class={expanded ? 'rotate-180' : ''} />
        </Button>
        {#if editMode === 'readonly'}
          <Button
            size="sm"
            variant="outline"
            onclick={startEditing}
            disabled={!session.atHead || !!session.pending || session.readOnly}
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
            disabled={!dirty || !!session.pending || session.readOnly}
          >
            {#if session.pending?.type === 'save' || session.pending?.type === 'save-html'}
              <Spinner data-icon="inline-start" />Compiling
            {:else}
              <SaveIcon data-icon="inline-start" />Save & render
            {/if}
          </Button>
        {/if}
      </header>

      {#if expanded && !session.atHead}
        <p class="border-b bg-muted px-4 py-2 text-xs text-muted-foreground">
          Historical source is read-only. Restore this event from the Timeline to make a new current
          version.
        </p>
      {/if}

      {#if expanded}
        <div class="min-h-48 flex-1 overflow-hidden">
          <CodeMirrorEditor
            bind:this={editor}
            value={displayedSource}
            editable={editMode === 'editing' &&
              session.atHead &&
              !session.pending &&
              !session.readOnly}
            ariaLabel="Project visualization source"
            onChange={updateDraft}
          />
        </div>
      {/if}
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
