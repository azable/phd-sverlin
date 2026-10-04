/**
 * Atomic types and their renderers. The presentation entry provides 'sverlin:types'; the authored
 * component registers its top-level type snippets under 'sverlin:renderers'.
 */

import { getContext, setContext, type Snippet } from 'svelte';

import type { NodeDefaults, NodeProps, Primitive } from './node/props';

export type TypeContext = {
  /** The atomic type name of item `index` of a container taken from the props, if typed. */
  itemType(container: unknown, index: number): string | undefined;
  /** The type a type refines, if any. */
  parent(typeName: string): string | undefined;
  /** A type's unit, or that of the nearest type it refines. */
  unit(typeName: string): string | undefined;
};

export type Renderer = Snippet<[Primitive, NodeProps]>;

export function typeContext(): TypeContext | undefined {
  return getContext<TypeContext | undefined>('sverlin:types');
}

/**
 * The renderer for a type, or for the nearest type it refines. A renderer is skipped while it is
 * already rendering, so a node inside it never calls it again.
 */
export function rendererFor(typeName: string): { name: string; snippet: Renderer } | undefined {
  const renderers = getContext<Record<string, Renderer> | undefined>('sverlin:renderers');
  const rendering = getContext<ReadonlySet<string> | undefined>('sverlin:rendering');
  const types = typeContext();
  for (let name: string | undefined = typeName; name; name = types?.parent(name)) {
    const snippet = renderers?.[name];
    if (snippet && !rendering?.has(name)) return { name, snippet };
  }
  return undefined;
}

/** Mark a renderer as rendering for the nodes inside it. */
export function markRendering(name: string): void {
  const rendering = getContext<ReadonlySet<string> | undefined>('sverlin:rendering');
  setContext('sverlin:rendering', new Set([...(rendering ?? []), name]));
}

/** The defaults this presentation drew (see node/defaults.ts), if any. */
export function defaultsContext(): NodeDefaults | undefined {
  return getContext<NodeDefaults | undefined>('sverlin:defaults');
}

/** Hands out the ids rendered nodes carry for selection; see provideNodeIds. */
export type NodeIds = { claim(ref: string): string };

/**
 * Give the nodes of one rendered step their ids. A node's id is its tag's source position (its
 * __ref, such as 12:5), then #2, #3, … for later renders of the same tag, such as inside a loop;
 * items a collection draws itself extend their collection's id with /index. Each step mounts
 * afresh and renders in the same order, so the same state always gives the same ids.
 */
export function provideNodeIds(): void {
  const counts = new Map<string, number>();
  setContext<NodeIds>('sverlin:node-ids', {
    claim(ref) {
      const count = (counts.get(ref) ?? 0) + 1;
      counts.set(ref, count);
      return count === 1 ? ref : `${ref}#${count}`;
    }
  });
}

export function nodeIdsContext(): NodeIds | undefined {
  return getContext<NodeIds | undefined>('sverlin:node-ids');
}
