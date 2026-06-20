<script lang="ts">
  import type { HTMLInputAttributes } from 'svelte/elements';

  import { cn } from '$lib/utils';

  type Props = Omit<HTMLInputAttributes, 'value'> & {
    value?: string;
  };

  let { value = $bindable(''), class: className, type = 'text', ...rest }: Props = $props();
</script>

<input
  class={cn(
    'h-9 rounded-md border border-slate-700 bg-slate-950/60 px-2.5 text-sm text-slate-100 transition-colors outline-none placeholder:text-slate-500 focus:border-sky-400 disabled:cursor-not-allowed disabled:opacity-45',
    className
  )}
  bind:value
  {type}
  {...rest}
/>
