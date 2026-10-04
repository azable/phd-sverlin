/** The authored Main.svelte after prelude injection, as the bundler supplies it to entry.ts. */
declare module 'virtual:component' {
  import type { Component } from 'svelte';

  const Main: Component<Record<string, unknown> & { step: number; seed: number }>;
  export default Main;
}

/** Top-level algorithm bindings recorded at each yield; one empty object per step without one. */
declare module 'virtual:trace' {
  const states: Record<string, unknown>[];
  export default states;
}
