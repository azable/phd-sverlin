<script lang="ts">
  import { Badge } from '$lib/components/ui/badge';
  import { Spinner } from '$lib/components/ui/spinner';
  import { presentProjectEvent } from '$lib/timeline/event-presentation';

  import type { ProjectSession } from './project-session.svelte';

  let { session }: { session: ProjectSession } = $props();

  const message = $derived.by(() => {
    const event = session.pendingEvent;
    if (event) return presentProjectEvent(event).progress;
    const action = session.pending?.action;
    if (session.connection === 'reconnecting') return 'Working; reconnecting live updates…';
    if (action === 'feedback') return 'Submitting feedback…';
    if (action === 'rename') return 'Renaming the project…';
    return 'Compiling and loading…';
  });
</script>

<Badge variant="secondary" role="status" aria-live="polite">
  <Spinner data-icon="inline-start" aria-label="Project operation in progress" />
  {message}
</Badge>
