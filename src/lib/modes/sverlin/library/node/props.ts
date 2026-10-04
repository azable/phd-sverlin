/** Every prop type of a Node, the props a type renderer receives, and the shape of drawn defaults. */

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

/** A stroke width; a number is a width in pixels. */
export type StrokeWidth = 'none' | 'thin' | 'thick' | number;

/** A stroke colour, or 'none' or false for no stroke. */
export type NodeStroke = NodeColor | 'none' | false;

/** The smallest a node may be; a number is a size in em instead. */
export type MinSize = 'none' | 'small' | 'medium' | 'large' | number;

export type Weight = 'normal' | 'bold';

/** The props a node was given, passed to its type's renderer so the caller's settings win. */
export type NodeProps = {
  shape?: NodeShape;
  fill?: NodeColor;
  stroke?: NodeStroke;
  opacity?: number;
  color?: NodeColor;
  font?: NodeFont;
  size?: NodeSize | number;
  weight?: Weight;
  padding?: Spacing;
  radius?: Radius;
  strokeWidth?: StrokeWidth;
  minSize?: MinSize;
};

/** Defaults one presentation drew for a framed shape (see defaults.ts). */
export type ShapeDefaults = {
  radius: Radius;
  strokeWidth: StrokeWidth;
  padding: Spacing;
  fill: string;
  stroke: string;
};

/** Defaults one presentation drew: per framed shape, the gap between items, and the page font. */
export type NodeDefaults = {
  box: ShapeDefaults;
  card: ShapeDefaults;
  gap: Spacing;
  font: NodeFont;
};
