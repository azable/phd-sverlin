<script lang="ts">
  import { onMount } from 'svelte';
  import { Compartment, EditorState } from '@codemirror/state';
  import { EditorView } from 'codemirror';

  import { artifactEditorExtensions, type ArtifactLanguage } from './artifact-editor';

  let {
    value = $bindable(''),
    editable = false,
    language = 'sverlin',
    ariaLabel = 'Source code editor',
    onChange
  }: {
    value: string;
    editable?: boolean;
    language?: ArtifactLanguage;
    ariaLabel?: string;
    onChange?: (value: string) => void;
  } = $props();

  let host = $state<HTMLElement | null>(null);
  let view: EditorView | null = null;
  let suppressChange = false;
  const editableCompartment = new Compartment();

  export function focus() {
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

  $effect(() => {
    if (!view) return;
    view.dispatch({ effects: editableCompartment.reconfigure(editableExtensions(editable)) });
  });

  function editableExtensions(isEditable: boolean) {
    return isEditable ? [] : [EditorView.editable.of(false), EditorState.readOnly.of(true)];
  }
</script>

<div bind:this={host} class="h-full min-h-0 overflow-hidden" aria-label={ariaLabel}></div>
