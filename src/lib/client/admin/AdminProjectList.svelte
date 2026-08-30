<script lang="ts">
  import { resolve } from '$app/paths';

  import { Badge } from '$lib/client/components/ui/badge';
  import { Button } from '$lib/client/components/ui/button';
  import type { ProjectSummary } from '$lib/shared/projects/model';

  type ListedProject = ProjectSummary & { ownerLabel?: string };
  type Props = { projects: ListedProject[]; emptyMessage: string; showOwner?: boolean };

  let { projects, emptyMessage, showOwner = false }: Props = $props();
</script>

{#if projects.length === 0}
  <p class="text-sm text-muted-foreground">{emptyMessage}</p>
{:else}
  <ul class="flex flex-col gap-2">
    {#each projects as project (project.projectId)}
      <li class="flex flex-wrap items-center gap-3 rounded-md border p-3">
        <div class="mr-auto min-w-0">
          <p class="truncate font-medium">{project.title}</p>
          <p class="text-xs text-muted-foreground">
            {#if showOwner}{project.ownerLabel ?? 'Administrator'} ·
            {/if}
            {project.eventCount} event{project.eventCount === 1 ? '' : 's'}
          </p>
        </div>
        <Badge variant="outline">{project.renderer === 'html' ? 'HTML' : 'Sverlin'}</Badge>
        <Button
          href={resolve('/projects/[projectId]', { projectId: project.projectId })}
          size="sm"
          variant="outline">Open</Button
        >
      </li>
    {/each}
  </ul>
{/if}
