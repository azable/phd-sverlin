/**
 * The sampling policy for unspecified Node props: which ones every presentation draws, and from which
 * options or ranges. Nodes use these drawn defaults wherever their own props and their type's
 * renderer leave a value unset, so each presentation has one consistent, seeded look. Drawing
 * takes its randomness from the caller, which keeps this module free of server code.
 */

import type {
  Align,
  FrameLayout,
  Justify,
  NodeDefaults,
  NodeFont,
  Radius,
  ShapeDefaults,
  Spacing,
  StrokeWidth
} from './props';

/** Choose one of a list of options. */
type Choice = { pick: readonly string[] };

/**
 * A pale surface tint and a matching border, drawn in HSL. Low saturation and high lightness keep
 * tints unlike the saturated palette colours authors give meaning, such as 'amber' or 'blue'.
 */
type TintRange = {
  /** Probability of the plain theme surface instead of a tint. */
  plain: number;
  hue: readonly [number, number];
  saturation: readonly [number, number];
  /** Fill lightness; the border is the same hue, darker. */
  lightness: readonly [number, number];
  borderLightness: readonly [number, number];
};

const tint: TintRange = {
  plain: 0.25,
  hue: [0, 360],
  saturation: [15, 40],
  lightness: [93, 97],
  borderLightness: [72, 82]
};

/** Every drawn default, by key. Edit this table to change what varies between presentations. */
export const defaultsPolicy = {
  'box.radius': { pick: ['small', 'medium', 'full'] },
  // 'none' lets some presentations draw no stroke where a node leaves its stroke unset.
  'box.strokeWidth': { pick: ['none', 'thin', 'thick'] },
  'box.padding': { pick: ['small', 'medium'] },
  'box.tint': tint,
  'card.radius': { pick: ['small', 'medium'] },
  'card.strokeWidth': { pick: ['none', 'thin', 'thick'] },
  'card.padding': { pick: ['small', 'medium', 'large'] },
  'card.tint': tint,
  // How a frame spreads and aligns its children, where the frame leaves them unset.
  'frame.justify': { pick: ['start', 'center', 'between', 'evenly'] },
  'frame.align': { pick: ['start', 'center'] },
  // A column of top-level nodes, or a free arrangement that differs with every seed.
  'frame.layout': { pick: ['column', 'free'] },
  gap: { pick: ['small', 'medium', 'large'] },
  font: { pick: ['sans', 'serif', 'mono'] }
} satisfies Record<string, Choice | TintRange>;

/**
 * Draw every default from a keyed random source, which returns a number in [0, 1) for each key.
 * Each value, down to a tint's hue, has its own key, so editing one entry of the policy never
 * changes the others.
 */
export function drawDefaults(random: (key: string) => number): NodeDefaults {
  const draw = (key: string) => random(`defaults.${key}`);
  const within = (key: string, [min, max]: readonly [number, number]) =>
    Math.round(min + draw(key) * (max - min));
  const choose = (key: keyof typeof defaultsPolicy) => {
    const options = (defaultsPolicy[key] as Choice).pick;
    return options[Math.floor(draw(key) * options.length)];
  };
  const drawTint = (key: string, range: TintRange) => {
    if (draw(`${key}.plain`) < range.plain)
      return { fill: 'var(--sv-surface)', stroke: 'var(--sv-line)' };
    const hue = within(`${key}.hue`, range.hue);
    const saturation = within(`${key}.saturation`, range.saturation);
    return {
      fill: `hsl(${hue} ${saturation}% ${within(`${key}.lightness`, range.lightness)}%)`,
      stroke: `hsl(${hue} ${saturation}% ${within(`${key}.borderLightness`, range.borderLightness)}%)`
    };
  };
  const shape = (name: 'box' | 'card'): ShapeDefaults => ({
    radius: choose(`${name}.radius`) as Radius,
    strokeWidth: choose(`${name}.strokeWidth`) as StrokeWidth,
    padding: choose(`${name}.padding`) as Spacing,
    ...drawTint(`${name}.tint`, defaultsPolicy[`${name}.tint`])
  });
  return {
    box: shape('box'),
    card: shape('card'),
    frame: {
      justify: choose('frame.justify') as Justify,
      align: choose('frame.align') as Align,
      layout: choose('frame.layout') as FrameLayout
    },
    gap: choose('gap') as Spacing,
    font: choose('font') as NodeFont
  };
}
