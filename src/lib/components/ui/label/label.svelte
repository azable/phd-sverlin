<script lang="ts">
  import type { Snippet } from 'svelte';
  import type { HTMLLabelAttributes } from 'svelte/elements';

  import { cn } from '$lib/utils';

  type Props = HTMLLabelAttributes & {
    children?: Snippet;
  };

  let { class: className, children, ...rest }: Props = $props();
</script>

<label
  class={cn('inline-flex items-center gap-2 text-sm font-medium text-slate-200', className)}
  {...rest}
>
  {@render children?.()}
</label>
