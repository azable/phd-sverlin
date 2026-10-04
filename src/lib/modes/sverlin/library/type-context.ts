/**
 * Atomic types and their renderers. The presentation entry provides 'sverlin:types'; the authored
 * component registers its top-level type snippets under 'sverlin:renderers'.
 */

import { getContext, setContext, type Snippet } from 'svelte';

import type { NodeFont, NodeRole, NodeShape, NodeSize, Primitive } from './types';

export type TypeContext = {
  /** The atomic type name of item `index` of a container taken from the props, if typed. */
  itemType(container: unknown, index: number): string | undefined;
  /** The type a type refines, if any. */
  parent(typeName: string): string | undefined;
  /** A type's unit, or that of the nearest type it refines. */
  unit(typeName: string): string | undefined;
};

/** The props a node was given, passed to its type's renderer so the caller's settings win. */
export type NodeProps = {
  role?: NodeRole;
  label?: string | number;
  marker?: string;
  shape?: NodeShape;
  font?: NodeFont;
  size?: NodeSize | number;
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
