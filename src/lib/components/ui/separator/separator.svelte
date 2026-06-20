<script lang="ts">
  import type { HTMLAttributes } from 'svelte/elements';

  import { cn } from '$lib/utils';

  type Props = HTMLAttributes<HTMLDivElement> & {
    orientation?: 'horizontal' | 'vertical';
  };

  let { class: className, orientation = 'horizontal', ...rest }: Props = $props();
</script>

<div
  aria-orientation={orientation}
  class={cn(
    'shrink-0 bg-slate-800',
    orientation === 'vertical' ? 'h-6 w-px' : 'h-px w-full',
    className
  )}
  role="separator"
  {...rest}
></div>
