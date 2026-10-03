<script lang="ts">
  import { sandboxDocument } from '../sandbox';
  import type { BrowserBundlePresentation } from '$lib/shared/presentations';

  let {
    presentation,
    step,
    label
  }: { presentation: BrowserBundlePresentation; step: number; label: string } = $props();
  const document = $derived(
    sandboxDocument(presentation.html.text, presentation.javascript.text, step, presentation.seed)
  );
</script>

<iframe
  title={label}
  srcdoc={document}
  sandbox="allow-scripts"
  referrerpolicy="no-referrer"
  class="h-full min-h-64 w-full border-0 bg-white"
></iframe>
