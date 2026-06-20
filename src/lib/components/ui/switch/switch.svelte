<script lang="ts">
  import type { HTMLButtonAttributes } from 'svelte/elements';

  import { cn } from '$lib/utils';

  type Props = Omit<HTMLButtonAttributes, 'type'> & {
    checked?: boolean;
  };

  let { checked = $bindable(false), class: className, disabled, ...rest }: Props = $props();

  function toggle() {
    if (disabled) return;

    checked = !checked;
  }
</script>

<button
  aria-checked={checked}
  class={cn(
    'relative inline-flex h-5 w-9 shrink-0 items-center rounded-full border border-slate-700 bg-slate-800 transition-colors outline-none disabled:cursor-not-allowed disabled:opacity-45 data-[state=checked]:border-sky-400 data-[state=checked]:bg-sky-500',
    className
  )}
  data-state={checked ? 'checked' : 'unchecked'}
  onclick={toggle}
  role="switch"
  type="button"
  {disabled}
  {...rest}
>
  <span
    class={cn(
      'block size-4 rounded-full bg-slate-100 shadow-sm transition-transform',
      checked ? 'translate-x-4' : 'translate-x-0.5'
    )}
  ></span>
</button>
