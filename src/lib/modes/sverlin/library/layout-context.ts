/** Lets an atom place its marker beside or below itself, following its collection's layout. */

import { getContext, setContext } from 'svelte';

import type { Layout } from './types';

const key = Symbol('sverlin-collection-layout');

export function provideLayout(layout: () => Layout): void {
  setContext(key, layout);
}

export function currentLayout(): Layout {
  return getContext<(() => Layout) | undefined>(key)?.() ?? 'row';
}
