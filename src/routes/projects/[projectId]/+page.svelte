<script lang="ts">
  import { page } from '$app/state';

  import ProjectWorkspace from '$lib/client/projects/ProjectWorkspace.svelte';

  const at = $derived.by(() => {
    const value = page.url.searchParams.get('at');
    if (value === null) return undefined;
    const id = Number(value);
    return Number.isSafeInteger(id) && id > 0 ? id : undefined;
  });
</script>

{#key page.params.projectId}
  <ProjectWorkspace projectId={page.params.projectId!} {at} />
{/key}
