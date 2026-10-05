<script lang="ts">
  import { onMount } from 'svelte';
  import { Compartment, EditorState } from '@codemirror/state';
  import { EditorView } from 'codemirror';

  import { artifactEditorExtensions, type ArtifactLanguage } from './artifact-editor';
  import {
    showSourceHighlights,
    sourceHighlights,
    type SourceHighlight
  } from './selection-highlights';

  /** Public properties accepted by the CodeMirror artifact editor. */
  type Props = {
    value: string;
    editable?: boolean;
    language?: ArtifactLanguage;
    ariaLabel?: string;
    /** Tags to highlight, such as those behind elements selected in a presentation. */
    highlights?: readonly SourceHighlight[];
    onChange?: (value: string) => void;
  };

  let {
    value = $bindable(''),
    editable = false,
    language = 'svelte',
    ariaLabel = 'Source code editor',
    highlights = [],
    onChange
  }: Props = $props();

  let host = $state<HTMLElement | null>(null);
  let view = $state.raw<EditorView | null>(null);
  let suppressChange = false;
  const editableCompartment = new Compartment();

  /** Focus the underlying CodeMirror editor. */
  export function focus(): void {
    view?.focus();
  }

  onMount(() => {
    if (!host) return;

    view = new EditorView({
      parent: host,
      state: EditorState.create({
        doc: value,
        extensions: [
          ...artifactEditorExtensions({ language }),
          sourceHighlights,
          editableCompartment.of(editableExtensions(editable)),
          EditorView.updateListener.of((update) => {
            if (suppressChange || !update.docChanged) return;
            const nextValue = update.state.doc.toString();
            value = nextValue;
            onChange?.(nextValue);
          })
        ]
      })
    });

    return () => {
      view?.destroy();
      view = null;
    };
  });

  $effect(() => {
    if (!view) return;

    const nextValue = value;
    if (view.state.doc.toString() !== nextValue) {
      suppressChange = true;
      view.dispatch({
        changes: {
          from: 0,
          to: view.state.doc.length,
          insert: nextValue
        }
      });
      suppressChange = false;
    }
  });

  // After the document, so highlights are placed in the text they refer to.
  $effect(() => {
    void value;
    const shown = [...highlights];
    if (view) view.dispatch(showSourceHighlights(view.state, shown));
  });

  $effect(() => {
    if (!view) return;
    view.dispatch({ effects: editableCompartment.reconfigure(editableExtensions(editable)) });
  });

  function editableExtensions(isEditable: boolean) {
    return isEditable ? [] : [EditorView.editable.of(false), EditorState.readOnly.of(true)];
  }
</script>

<div bind:this={host} class="h-full min-h-0 overflow-hidden" aria-label={ariaLabel}></div>
