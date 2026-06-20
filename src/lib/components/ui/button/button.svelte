<script lang="ts">
  import type { Snippet } from 'svelte';
  import type { HTMLButtonAttributes } from 'svelte/elements';

  import { cn } from '$lib/utils';

  type ButtonVariant = 'default' | 'outline' | 'secondary' | 'ghost';
  type ButtonSize = 'default' | 'sm' | 'icon';

  type Props = HTMLButtonAttributes & {
    variant?: ButtonVariant;
    size?: ButtonSize;
    children?: Snippet;
  };

  const base =
    'inline-flex shrink-0 items-center justify-center gap-1.5 whitespace-nowrap rounded-md border text-sm font-medium outline-none transition-colors disabled:pointer-events-none disabled:opacity-45';
  const variants: Record<ButtonVariant, string> = {
    default: 'border-sky-500 bg-sky-500 text-slate-950 hover:bg-sky-400',
    outline: 'border-slate-700 bg-slate-950/40 text-slate-100 hover:bg-slate-800',
    secondary: 'border-slate-700 bg-slate-800 text-slate-100 hover:bg-slate-700',
    ghost: 'border-transparent bg-transparent text-slate-200 hover:bg-slate-800'
  };
  const sizes: Record<ButtonSize, string> = {
    default: 'h-9 px-3',
    sm: 'h-8 px-2.5',
    icon: 'size-9'
  };

  let {
    class: className,
    variant = 'default',
    size = 'default',
    type = 'button',
    children,
    ...rest
  }: Props = $props();
</script>

<button class={cn(base, variants[variant], sizes[size], className)} {type} {...rest}>
  {@render children?.()}
</button>
