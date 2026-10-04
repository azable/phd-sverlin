/** Shared prop vocabulary for the sverlin component library. */

/** A single value a node can display. */
export type Primitive = string | number | boolean | null;

/** How a node with items arranges its children. */
export type Layout = 'row' | 'column' | 'wrap' | 'grid';

/** The frame a node is drawn in. */
export type NodeShape = 'box' | 'plain' | 'card' | 'circle';

/** A theme palette colour, giving a light shade as a fill and a strong shade as a stroke. */
export type PaletteColor = 'neutral' | 'blue' | 'green' | 'amber' | 'red' | 'purple';

/** A palette colour name, or any other CSS colour. */
export type NodeColor = PaletteColor | (string & {});

/** Font family of a node, from the system fonts the sandbox can use. */
export type NodeFont = 'sans' | 'serif' | 'mono';

/** Named node text size; a number is a size in rem instead. */
export type NodeSize = 'small' | 'medium' | 'large' | 'xlarge';
