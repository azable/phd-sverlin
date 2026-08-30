<script lang="ts">
  import { resolve } from '$app/paths';

  import { cn } from '$lib/client/components/utils';
  import type { StudyFlow, StudyFlowPhase } from '$lib/shared/study/projection';

  import StudyStatusBadge from './StudyStatusBadge.svelte';
  import StudyTimer from './StudyTimer.svelte';
  import { studyStatusSurfaceClasses } from './study-status';

  type Props = { flow: StudyFlow; linkProjects?: boolean; showHeader?: boolean };
  let { flow, linkProjects = true, showHeader = true }: Props = $props();

  function phaseTitle(item: StudyFlowPhase): string {
    return item.phase.kind === 'task' ? item.phase.instructions.title : item.phase.title;
  }
</script>

<section class="flex min-w-0 flex-col gap-3" aria-label={`${flow.studyName} flow`}>
  {#if showHeader}
    <div class="flex flex-wrap items-center gap-2">
      <p class="font-medium">
        {flow.studyName} <span class="text-muted-foreground">v{flow.studyVersion}</span>
      </p>
      <StudyStatusBadge status={flow.status} />
      <span class="text-xs text-muted-foreground">Arm: {flow.armId}</span>
    </div>
  {/if}
  <ol class="grid gap-2 sm:grid-cols-[repeat(auto-fit,minmax(9rem,1fr))]">
    {#each flow.phases as item (item.phase.id)}
      <li
        class={cn(
          'flex min-w-0 flex-col gap-2 rounded-md border p-3',
          studyStatusSurfaceClasses[item.status],
          item.status === 'active' &&
            'border-status-info-foreground/30 ring-1 ring-status-info-foreground/20',
          item.status === 'ready-to-continue' &&
            'border-status-warning-foreground/30 ring-1 ring-status-warning-foreground/20',
          item.status === 'completed' && 'border-status-success-foreground/20',
          item.status === 'out-of-scope' && 'opacity-50'
        )}
        aria-current={item.status === 'active' || item.status === 'ready-to-continue'
          ? 'step'
          : undefined}
      >
        <div class="flex items-start justify-between gap-2">
          <span class="text-xs text-muted-foreground">{item.sequenceIndex + 1}</span>
          <StudyStatusBadge status={item.status} />
        </div>
        <div class="min-w-0">
          {#if item.projectId && linkProjects}
            <a
              class="font-medium underline-offset-4 hover:underline"
              href={resolve('/projects/[projectId]', { projectId: item.projectId })}
              >{phaseTitle(item)}</a
            >
          {:else}
            <p class="font-medium">{phaseTitle(item)}</p>
          {/if}
          <p class="text-xs text-muted-foreground">
            {item.phase.kind === 'task' ? item.phase.condition.renderer : item.phase.kind}
          </p>
        </div>
        {#if item.status === 'active' && item.deadlineAt}
          <div class="mt-auto text-xs text-muted-foreground">
            Remaining: <StudyTimer deadlineAt={item.deadlineAt} />
          </div>
        {/if}
      </li>
    {/each}
  </ol>
</section>
