<script lang="ts">
  import SendIcon from '@lucide/svelte/icons/send';
  import XIcon from '@lucide/svelte/icons/x';

  import { Badge } from '$lib/client/components/ui/badge';
  import { Button } from '$lib/client/components/ui/button';
  import * as Field from '$lib/client/components/ui/field';
  import { Spinner } from '$lib/client/components/ui/spinner';
  import type { ProjectSession } from '$lib/client/projects/project-session.svelte';
  import {
    presentationDisplayId,
    timelinePresentations,
    type TimelinePresentation
  } from '$lib/client/visualization/presentation-history';
  import type {
    MessageContent,
    MessageContentSegment
  } from '$lib/shared/projects/events/message-content';
  import type { VisualSelection } from '$lib/shared/projects/events/values';

  type ReferenceSegment = Exclude<MessageContentSegment, { type: 'markdown' }>;

  type Props = {
    session: ProjectSession;
    presentationCount: 1 | 2;
  };

  let { session, presentationCount }: Props = $props();
  let editor = $state<HTMLDivElement>();
  let savedRange: Range | undefined;
  let hasContent = $state(false);
  let editorRevision = $state(0);

  export function referencePresentation(presentation: TimelinePresentation): void {
    insertReference({
      type: 'presentation-ref',
      presentationId: presentation.presentation.presentationId
    });
  }

  export function referenceSelection(selection: VisualSelection): void {
    const presentation = timelinePresentations(session.events).find(
      ({ eventId }) => eventId === selection.presentationEvent
    );
    if (!presentation) return;
    insertReference({
      type: 'element-ref',
      presentationId: presentation.presentation.presentationId,
      presentationEvent: selection.presentationEvent,
      step: selection.step,
      instances: selection.instances
    });
  }

  async function submit(event: SubmitEvent) {
    event.preventDefault();
    if (!editor || !session.atHead || session.pending || session.readOnly) return;
    const content = serializeEditor();
    if (content.length === 0) return;
    const succeeded = await session.runCommand({
      type: 'feedback',
      content,
      focus: session.focusedEvents,
      presentationCount
    });
    if (succeeded) {
      editorRevision += 1;
      hasContent = false;
      savedRange = undefined;
      session.focusedEvents = [];
    }
  }

  function submitOnEnter(event: KeyboardEvent) {
    if (event.key !== 'Enter' || event.shiftKey || event.isComposing) return;
    event.preventDefault();
    editor?.closest('form')?.requestSubmit();
  }

  function rememberSelection() {
    if (!editor) return;
    const selection = window.getSelection();
    const range = selection?.rangeCount ? selection.getRangeAt(0) : undefined;
    if (range && editor.contains(range.commonAncestorContainer)) savedRange = range.cloneRange();
  }

  function updateContentState() {
    rememberSelection();
    hasContent = serializeEditor().length > 0;
  }

  function insertReference(reference: ReferenceSegment) {
    if (!editor || session.readOnly || !session.atHead) return;
    editor.focus();
    const range =
      savedRange && editor.contains(savedRange.commonAncestorContainer)
        ? savedRange
        : document.createRange();
    if (!savedRange || !editor.contains(savedRange.commonAncestorContainer)) {
      range.selectNodeContents(editor);
      range.collapse(false);
    }
    const chip = referenceChip(reference);
    const spacer = document.createTextNode('\u00a0');
    range.deleteContents();
    range.insertNode(spacer);
    range.insertNode(chip);
    range.setStartAfter(spacer);
    range.collapse(true);
    const selection = window.getSelection();
    selection?.removeAllRanges();
    selection?.addRange(range);
    savedRange = range.cloneRange();
    hasContent = true;
  }

  function referenceChip(reference: ReferenceSegment): HTMLSpanElement {
    const chip = document.createElement('span');
    chip.contentEditable = 'false';
    chip.dataset.reference = JSON.stringify(reference);
    chip.className =
      'mx-0.5 inline-flex items-center gap-1 rounded-md border bg-muted px-1.5 py-0.5 align-baseline font-mono text-sm text-foreground';
    const label = document.createElement('span');
    label.textContent = referenceLabel(reference);
    const remove = document.createElement('button');
    remove.type = 'button';
    remove.setAttribute('aria-label', `Remove reference ${label.textContent}`);
    remove.className = 'rounded-sm text-muted-foreground hover:text-foreground';
    remove.textContent = '×';
    remove.onclick = () => {
      chip.remove();
      updateContentState();
      editor?.focus();
    };
    chip.append(label, remove);
    return chip;
  }

  function referenceLabel(reference: ReferenceSegment): string {
    const presentation = presentationDisplayId(reference.presentationId);
    return reference.type === 'presentation-ref'
      ? presentation
      : `${reference.instances.length} element${reference.instances.length === 1 ? '' : 's'} · ${presentation} · Step ${reference.step + 1}`;
  }

  function serializeEditor(): MessageContent {
    if (!editor) return [];
    const segments: MessageContent = [];
    let markdown = '';
    const flush = () => {
      if (markdown) segments.push({ type: 'markdown', text: markdown });
      markdown = '';
    };
    const visit = (node: Node) => {
      if (node.nodeType === Node.TEXT_NODE) {
        markdown += node.textContent ?? '';
        return;
      }
      if (!(node instanceof HTMLElement)) return;
      if (node.dataset.reference) {
        flush();
        segments.push(JSON.parse(node.dataset.reference) as ReferenceSegment);
        return;
      }
      if (node.tagName === 'BR') {
        markdown += '\n';
        return;
      }
      const block = node !== editor && (node.tagName === 'DIV' || node.tagName === 'P');
      for (const child of node.childNodes) visit(child);
      if (block) markdown += '\n';
    };
    visit(editor);
    flush();
    const normalized = segments
      .map((segment, index) => {
        if (segment.type !== 'markdown') return segment;
        let text = segment.text;
        if (index === 0) text = text.trimStart();
        else if (segments[index - 1]?.type !== 'markdown') text = text.replace(/^\u00a0/, '');
        if (index === segments.length - 1) text = text.trimEnd();
        else if (segments[index + 1]?.type !== 'markdown') text = text.replace(/\u00a0$/, '');
        return { ...segment, text };
      })
      .filter((segment) => segment.type !== 'markdown' || segment.text.length > 0);
    return normalized as MessageContent;
  }
</script>

<form class="border-t bg-background p-4" onsubmit={submit}>
  <Field.FieldGroup>
    <Field.Field>
      {#if session.focusedEvents.length > 0}
        <div class="flex flex-wrap gap-2">
          {#each session.focusedEvents as id (id)}
            <Badge variant="secondary">
              Event #{id}
              <button
                type="button"
                aria-label={`Remove event ${id}`}
                onclick={() => session.removeFocus(id)}
              >
                <XIcon class="size-3" />
              </button>
            </Badge>
          {/each}
        </div>
      {/if}
      <div
        class="overflow-hidden rounded-md border bg-background focus-within:ring-2 focus-within:ring-ring"
      >
        {#key editorRevision}
          <div
            bind:this={editor}
            class="message-editor min-h-20 px-3 py-2 text-base outline-none"
            contenteditable={!session.readOnly && session.atHead && !session.pending}
            tabindex={session.readOnly ? -1 : 0}
            role="textbox"
            aria-label="Project feedback"
            aria-multiline="true"
            data-placeholder="Comment on the project or reference a visualization…"
            oninput={updateContentState}
            onkeyup={rememberSelection}
            onmouseup={rememberSelection}
            onfocusout={rememberSelection}
            onkeydown={submitOnEnter}
          ></div>
        {/key}
        <div class="flex items-center gap-2 border-t px-2 py-1.5">
          <span class="mr-auto text-sm text-muted-foreground">
            {session.atHead
              ? 'Enter submits · Shift+Enter adds a line'
              : 'Return to present to respond'}
          </span>
          <Button
            type="submit"
            size="sm"
            disabled={!session.atHead || !!session.pending || session.readOnly || !hasContent}
          >
            {#if session.pending?.type === 'feedback'}
              <Spinner data-icon="inline-start" />Thinking
            {:else}
              <SendIcon data-icon="inline-start" />Submit
            {/if}
          </Button>
        </div>
      </div>
    </Field.Field>
  </Field.FieldGroup>
</form>

<style>
  .message-editor:empty::before {
    color: var(--muted-foreground);
    content: attr(data-placeholder);
    pointer-events: none;
  }
</style>
