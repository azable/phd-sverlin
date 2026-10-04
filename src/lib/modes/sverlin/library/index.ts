/** The `sverlin` module; ../assembly/prelude.ts imports Node from it into every authored component. */

export { default as Node } from './node/Node.svelte';
export { themeCss } from './theme';
export type {
  Align,
  Layout,
  MinSize,
  NodeColor,
  NodeDefaults,
  NodeFont,
  NodeProps,
  NodeShape,
  NodeSize,
  NodeStroke,
  PaletteColor,
  Primitive,
  Radius,
  Spacing,
  StrokeWidth,
  Weight
} from './node/props';
