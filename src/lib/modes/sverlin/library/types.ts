/** Shared prop vocabulary for the sverlin component library. */

/** A single value a node can display. */
export type Primitive = string | number | boolean | null;

/** How a node arranges its items or children. */
export type Layout = 'row' | 'column' | 'wrap' | 'grid';

/** How arranged items line up across the layout direction. */
export type Align = 'start' | 'center' | 'end';

/** A preset of frame, spacing, and text defaults that a node's own props override. */
export type NodeShape = 'box' | 'card' | 'plain';

/** A theme palette colour, giving a light shade as a fill and a strong shade as a stroke or text. */
export type PaletteColor = 'neutral' | 'blue' | 'green' | 'amber' | 'red' | 'purple';

/** A palette colour name, or any other CSS colour. */
export type NodeColor = PaletteColor | (string & {});

/** Font family of a node, from the system fonts the sandbox can use. */
export type NodeFont = 'sans' | 'serif' | 'mono';

/** Named node text size; a number is a size in rem instead. */
export type NodeSize = 'small' | 'medium' | 'large' | 'xlarge';

/** Named spacing for padding and gaps; a number is a size in em instead. */
export type Spacing = 'none' | 'small' | 'medium' | 'large' | number;

/** Corner rounding; 'full' gives a circle or pill. */
export type Radius = 'none' | 'small' | 'medium' | 'full';

export type Border = 'none' | 'thin' | 'thick';

/** The smallest a node may be; a number is a size in em instead. */
export type MinSize = 'none' | 'small' | 'medium' | 'large' | number;

export type Weight = 'normal' | 'bold';
