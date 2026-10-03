<script lang="ts">
  import * as v from 'valibot';
  import {
    htmlFramesManifestSchema,
    staticHtmlFrameDocument,
    type HtmlFramesPresentation
  } from '$lib/shared/presentations';

  let {
    presentation,
    step,
    label
  }: { presentation: HtmlFramesPresentation; step: number; label: string } = $props();
  const document = $derived.by(() => {
    const manifest = v.parse(htmlFramesManifestSchema, JSON.parse(presentation.rendered.text));
    const frame = manifest.frames[Math.min(step, manifest.frames.length - 1)];
    return frame ? staticHtmlFrameDocument(frame.html) : undefined;
  });
</script>

{#if document}
  <iframe
    title={label}
    srcdoc={document}
    sandbox=""
    referrerpolicy="no-referrer"
    class="h-full min-h-64 w-full border-0 bg-white"
  ></iframe>
{/if}
