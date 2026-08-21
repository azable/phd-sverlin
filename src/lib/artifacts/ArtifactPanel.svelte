<script lang="ts">
  import { tick } from 'svelte';

  import AlertCircleIcon from '@lucide/svelte/icons/circle-alert';
  import Edit3Icon from '@lucide/svelte/icons/edit-3';
  import HistoryIcon from '@lucide/svelte/icons/history';
  import RefreshCwIcon from '@lucide/svelte/icons/refresh-cw';
  import SaveIcon from '@lucide/svelte/icons/save';
  import XIcon from '@lucide/svelte/icons/x';

  import * as Alert from '$lib/components/ui/alert';
  import * as AlertDialog from '$lib/components/ui/alert-dialog';
  import { Badge } from '$lib/components/ui/badge';
  import { Button } from '$lib/components/ui/button';
  import { ScrollArea } from '$lib/components/ui/scroll-area';
  import { Spinner } from '$lib/components/ui/spinner';
  import CodeMirrorDiff from './CodeMirrorDiff.svelte';
  import CodeMirrorEditor from './CodeMirrorEditor.svelte';
  import { ChatState } from '$lib/chat/chat-state.svelte';
  import type { ArtifactChangeEvent, ArtifactEditMode, ArtifactSyncState } from './types';

  let {
    chat,
    editMode = $bindable<ArtifactEditMode>('readonly')
  }: { chat: ChatState; editMode?: ArtifactEditMode } = $props();

  let draftContent = $state('');
  let baseRevision = $state(0);
  let saving = $state(false);
  let error = $state<string | null>(null);
  let discardRequested = $state(false);
  let selectedEventId = $state<string | null>(null);
  let editor = $state<{ focus: () => void } | null>(null);
  let lastServerRevision = $state<number | null>(null);

  const artifact = $derived(chat.artifact);
  const events = $derived(artifact?.events ?? []);
  const selectedEvent = $derived(
    events.find((event) => event.eventId === selectedEventId) ?? events.at(-1) ?? null
  );
  const dirty = $derived(artifact !== null && draftContent !== artifact.current.content);
  const locked = $derived(editMode !== 'readonly');

  $effect(() => {
    if (!artifact) return;

    if (lastServerRevision === null) {
      lastServerRevision = artifact.headRevision;
      draftContent = artifact.current.content;
      baseRevision = artifact.headRevision;
      selectedEventId = events.at(-1)?.eventId ?? null;
      return;
    }

    if (artifact.headRevision === lastServerRevision) return;
    lastServerRevision = artifact.headRevision;

    if (editMode === 'readonly') {
      draftContent = artifact.current.content;
      baseRevision = artifact.headRevision;
      error = null;
      return;
    }

    if (draftContent !== artifact.current.content) {
      editMode = 'conflict';
      error =
        'The source changed elsewhere while you were editing. Review the difference before choosing how to continue.';
    } else {
      draftContent = artifact.current.content;
      baseRevision = artifact.headRevision;
    }
  });

  function startEditing() {
    if (!artifact || editMode !== 'readonly') return;
    draftContent = artifact.current.content;
    baseRevision = artifact.headRevision;
    error = null;
    discardRequested = false;
    editMode = 'editing';
    void tick().then(() => editor?.focus());
  }

  function requestCancel() {
    if (!dirty) {
      exitEditing();
      return;
    }
    discardRequested = true;
  }

  function discardDraft() {
    if (!artifact) return;
    draftContent = artifact.current.content;
    baseRevision = artifact.headRevision;
    discardRequested = false;
    error = null;
    editMode = 'readonly';
  }

  function exitEditing() {
    discardRequested = false;
    error = null;
    editMode = 'readonly';
  }

  async function saveDraft() {
    if (!artifact || saving || editMode !== 'editing' || !dirty) return;
    await persistDraft(baseRevision);
  }

  async function retryDraft() {
    if (!artifact || saving || editMode !== 'conflict') return;
    await persistDraft(artifact.headRevision);
  }

  async function persistDraft(revision: number) {
    if (!artifact) return;
    saving = true;
    error = null;

    try {
      const response = await fetch(`/api/artifacts/${artifact.artifactId}`, {
        method: 'PATCH',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          content: draftContent,
          baseRevision: revision,
          reason: 'manual editor save'
        })
      });
      const payload = (await response.json().catch(() => null)) as {
        error?: string;
        state?: ArtifactSyncState;
      } & Partial<ArtifactSyncState>;

      if (!payload || typeof payload !== 'object') {
        error = 'The source update returned an unreadable response.';
        return;
      }

      if (response.ok) {
        const nextState = payload as ArtifactSyncState;
        chat.applyArtifactState(nextState);
        draftContent = nextState.current.content;
        baseRevision = nextState.headRevision;
        lastServerRevision = nextState.headRevision;
        editMode = 'readonly';
        discardRequested = false;
        return;
      }

      if (response.status === 409 && payload.state) {
        chat.applyArtifactState(payload.state);
        editMode = 'conflict';
        error = payload.error ?? 'The source changed before the save completed.';
        return;
      }

      error = payload.error ?? 'The source could not be saved.';
    } catch (cause) {
      error = cause instanceof Error ? cause.message : 'The source could not be saved.';
    } finally {
      saving = false;
    }
  }

  function reloadServerVersion() {
    if (!artifact) return;
    draftContent = artifact.current.content;
    baseRevision = artifact.headRevision;
    error = null;
    discardRequested = false;
    editMode = 'readonly';
  }

  function formatTimestamp(value: string) {
    return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
      new Date(value)
    );
  }

  function sourceLabel(event: ArtifactChangeEvent) {
    switch (event.source.kind) {
      case 'chat':
        return 'Chat';
      case 'manual':
        return 'Manual';
      case 'feedback':
        return 'Feedback';
    }
  }
</script>

<section class="flex h-full min-h-0 flex-col gap-3 p-4" aria-label="DSL artefact authoring">
  {#if artifact}
    <div class="flex min-h-0 flex-[3] flex-col overflow-hidden rounded-xl border bg-card">
      <div class="flex flex-wrap items-center gap-2 border-b px-4 py-3">
        <div class="mr-auto flex min-w-0 items-center gap-2">
          <Edit3Icon class="size-4 shrink-0 text-muted-foreground" />
          <div class="min-w-0">
            <p class="truncate font-mono text-xs">{artifact.current.path}</p>
            <p class="text-xs text-muted-foreground">Sverlin · Haskell profile</p>
          </div>
          <Badge variant="outline">Revision {artifact.headRevision}</Badge>
        </div>
        {#if editMode === 'readonly'}
          <Button size="sm" variant="outline" onclick={startEditing}>
            <Edit3Icon data-icon="inline-start" />Edit
          </Button>
        {:else if editMode === 'editing'}
          <Badge variant="secondary">Editing · controls locked</Badge>
          <Button size="sm" variant="ghost" onclick={requestCancel} disabled={saving}>
            <XIcon data-icon="inline-start" />Cancel
          </Button>
          <Button size="sm" onclick={saveDraft} disabled={!dirty || saving}>
            {#if saving}<Spinner data-icon="inline-start" />Saving{:else}<SaveIcon
                data-icon="inline-start"
              />Save{/if}
          </Button>
        {:else}
          <Badge variant="destructive">Conflict</Badge>
          <Button size="sm" variant="ghost" onclick={reloadServerVersion} disabled={saving}>
            <RefreshCwIcon data-icon="inline-start" />Reload server
          </Button>
          <Button size="sm" onclick={retryDraft} disabled={saving}>
            {#if saving}<Spinner data-icon="inline-start" />Retrying{:else}<SaveIcon
                data-icon="inline-start"
              />Keep draft & retry{/if}
          </Button>
        {/if}
      </div>

      {#if editMode === 'editing'}
        <div class="border-b px-4 py-2 text-xs text-muted-foreground" role="status">
          Chat, trace playback, regeneration, and history selection are paused until you save or
          cancel.
        </div>
      {/if}

      {#if editMode === 'conflict'}
        <Alert.Root variant="destructive" class="m-3 mb-0">
          <AlertCircleIcon />
          <Alert.Title>Source conflict</Alert.Title>
          <Alert.Description>
            {error ?? 'The server has a newer revision.'} Choose whether to reload it or keep this draft
            and retry.
          </Alert.Description>
        </Alert.Root>
        <div class="m-3 mb-0 h-48 min-h-0 overflow-hidden rounded-lg border">
          <CodeMirrorDiff
            value={draftContent}
            original={artifact.current.content}
            ariaLabel="Draft compared with server source"
          />
        </div>
      {:else if error}
        <Alert.Root variant="destructive" class="m-3 mb-0">
          <Alert.Title>Unable to save source</Alert.Title>
          <Alert.Description>{error}</Alert.Description>
        </Alert.Root>
      {/if}

      <div class="min-h-0 flex-1 overflow-hidden p-3">
        <CodeMirrorEditor
          bind:this={editor}
          bind:value={draftContent}
          editable={editMode === 'editing'}
          ariaLabel="DSL source editor"
        />
      </div>
    </div>

    <div class="flex min-h-0 flex-[2] flex-col overflow-hidden rounded-xl border bg-card">
      <div class="flex items-center gap-2 border-b px-4 py-3">
        <HistoryIcon class="size-4 text-muted-foreground" />
        <div class="mr-auto">
          <p class="text-sm font-medium">Edit history</p>
          <p class="text-xs text-muted-foreground">
            Complete audit trail · {events.length} revisions
          </p>
        </div>
      </div>
      <div class="grid min-h-0 flex-1 grid-cols-[minmax(12rem,0.8fr)_minmax(0,2fr)]">
        <ScrollArea class="min-h-0 border-r">
          <div class="flex flex-col gap-1 p-2">
            {#if events.length === 0}
              <p class="p-2 text-xs text-muted-foreground">No changes yet.</p>
            {:else}
              {#each events as event (event.eventId)}
                <button
                  type="button"
                  class="flex flex-col gap-1 rounded-lg px-3 py-2 text-left text-xs transition-colors hover:bg-muted disabled:pointer-events-none disabled:opacity-50"
                  class:bg-muted={selectedEvent?.eventId === event.eventId}
                  onclick={() => (selectedEventId = event.eventId)}
                  disabled={locked}
                >
                  <span class="flex items-center gap-2 font-medium">
                    <Badge variant="outline">r{event.revision}</Badge>
                    <span>{sourceLabel(event)}</span>
                  </span>
                  <span class="text-muted-foreground">{formatTimestamp(event.createdAt)}</span>
                  {#if event.source.kind === 'manual' && event.source.reason}
                    <span class="truncate text-muted-foreground">{event.source.reason}</span>
                  {/if}
                </button>
              {/each}
            {/if}
          </div>
        </ScrollArea>
        <div class="min-h-0 overflow-hidden p-3">
          {#if selectedEvent}
            <CodeMirrorDiff
              value={selectedEvent.after.content}
              original={selectedEvent.before.content}
              ariaLabel="Selected source revision diff"
            />
          {:else}
            <div class="flex h-full items-center justify-center text-sm text-muted-foreground">
              Select a revision to inspect its diff.
            </div>
          {/if}
        </div>
      </div>
    </div>
  {:else}
    <div class="flex h-full items-center justify-center text-sm text-muted-foreground">
      Loading DSL artefact…
    </div>
  {/if}

  <AlertDialog.Root bind:open={discardRequested}>
    <AlertDialog.Content>
      <AlertDialog.Header>
        <AlertDialog.Title>Discard unsaved changes?</AlertDialog.Title>
        <AlertDialog.Description>
          Your draft will be replaced by the server revision.
        </AlertDialog.Description>
      </AlertDialog.Header>
      <AlertDialog.Footer>
        <AlertDialog.Cancel>Keep editing</AlertDialog.Cancel>
        <AlertDialog.Action variant="destructive" onclick={discardDraft}
          >Discard draft</AlertDialog.Action
        >
      </AlertDialog.Footer>
    </AlertDialog.Content>
  </AlertDialog.Root>
</section>
