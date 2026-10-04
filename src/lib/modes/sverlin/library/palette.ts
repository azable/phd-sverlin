/** Theme palette colours for node fills and strokes; other values pass through as CSS colours. */

import type { NodeColor, PaletteColor } from './types';

const palette: Record<PaletteColor, { fill: string; stroke: string }> = {
  neutral: { fill: 'var(--sv-surface)', stroke: 'var(--sv-line)' },
  blue: { fill: 'var(--sv-blue)', stroke: 'var(--sv-blue-line)' },
  green: { fill: 'var(--sv-green)', stroke: 'var(--sv-green-line)' },
  amber: { fill: 'var(--sv-amber)', stroke: 'var(--sv-amber-line)' },
  red: { fill: 'var(--sv-red)', stroke: 'var(--sv-red-line)' },
  purple: { fill: 'var(--sv-purple)', stroke: 'var(--sv-purple-line)' }
};

/** The CSS colour for a fill or stroke: a palette shade, or the value itself. */
export function paletteColor(
  color: NodeColor | undefined,
  use: 'fill' | 'stroke'
): string | undefined {
  if (color === undefined) return undefined;
  return Object.hasOwn(palette, color) ? palette[color as PaletteColor][use] : color;
}
