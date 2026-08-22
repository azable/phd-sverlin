<script lang="ts">
  import ProjectWorkspace from '$lib/projects/ProjectWorkspace.svelte';

  import type { PageProps } from './$types';

  let { data }: PageProps = $props();
</script>

{#key data.document.projectId}
  <ProjectWorkspace {data} />
{/key}
