<script lang="ts">
  import { EditorState } from '@codemirror/state';
  import { unifiedMergeView } from '@codemirror/merge';
  import { EditorView } from 'codemirror';

  import { artifactEditorExtensions, type ArtifactLanguage } from './artifact-editor';

  let {
    value,
    original,
    language = 'haskell',
    ariaLabel = 'Source revision diff'
  }: {
    value: string;
    original: string;
    language?: ArtifactLanguage;
    ariaLabel?: string;
  } = $props();

  let host = $state<HTMLElement | null>(null);
  let view: EditorView | null = null;

  $effect(() => {
    if (!host) return;

    const nextValue = value;
    const nextOriginal = original;
    view?.destroy();
    view = new EditorView({
      parent: host,
      state: EditorState.create({
        doc: nextValue,
        extensions: [
          ...artifactEditorExtensions({ language }),
          EditorView.editable.of(false),
          EditorState.readOnly.of(true),
          unifiedMergeView({ original: nextOriginal, mergeControls: false })
        ]
      })
    });

    return () => {
      view?.destroy();
      view = null;
    };
  });
</script>

<div bind:this={host} class="h-full min-h-0 overflow-hidden" aria-label={ariaLabel}></div>
