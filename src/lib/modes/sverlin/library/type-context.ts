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

/** Make the presentation's seed available to library components that vary by it. */
export function provideSeed(seed: number): void {
  setContext('sverlin:seed', seed);
}

export function seedContext(): number {
  return getContext<number | undefined>('sverlin:seed') ?? 1;
}

/** The arrangement around a node, told when a nested arrangement's size settles. */
export type ArrangementParent = { changed(): void };

export function provideArrangementParent(parent: ArrangementParent): void {
  setContext('sverlin:arrangement', parent);
}

export function arrangementParentContext(): ArrangementParent | undefined {
  return getContext<ArrangementParent | undefined>('sverlin:arrangement');
}

/** One arrangement's layout at one step, recorded so any later showing of that step replays it. */
export type LayoutRecord = {
  /** Child sizes the layout was made for, by key; a replay needs the same children and sizes. */
  sizes: Record<string, { width: number; height: number }>;
  /** Child centres in the solver's coordinates, to start the next step's layout from. */
  centres: Record<string, { x: number; y: number }>;
  /** The top-left of everything placed, in the solver's coordinates. */
  origin: { x: number; y: number };
  placements: { key: string; x: number; y: number }[];
  edges: { x1: number; y1: number; x2: number; y2: number; directed: boolean }[];
};

/**
 * Layouts for every step of a presentation, made once in step order when the page loads: each step
 * starts from the one before, each arrangement keeps the bounds of all its steps, and the root the
 * smallest fit any step needs. Showing a step replays its record, so a seed always gives the same
 * layout for a step, whichever step is shown first, and what does not change stays put.
 */
export type LayoutMemory = {
  /** The step being laid out or shown. */
  step: number;
  /** True while making the records; false when showing a step from them. */
  recording: boolean;
  /** True while only measuring each node's natural size, before the records are made. */
  measuring?: boolean;
  /**
   * The largest size each node reaches at any step, by id. Nodes keep it as their least size, so a box
   * whose content changes keeps one size and nothing around it moves.
   */
  reserved: Map<string, { width: number; height: number }>;
  scopes: Map<
    string,
    {
      steps: Map<number, LayoutRecord>;
      bounds?: { left: number; top: number; right: number; bottom: number };
    }
  >;
  /** The root's fit at each step. */
  fits: Map<number, number>;
};

export function layoutMemoryContext(): LayoutMemory | undefined {
  return getContext<LayoutMemory | undefined>('sverlin:layout-memory');
}
