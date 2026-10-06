/** The named scales that turn Node prop values into CSS. */

import type { FrameRatio, NodeSize } from './props';

export const spacings = { none: '0', small: '0.4em', medium: '0.75em', large: '1.25em' };
export const radii = { none: '0', small: '0.25rem', medium: 'var(--sv-radius)', full: '9999px' };
export const strokeWidths = { none: '0', thin: '2px', thick: '4px' };
export const minSizes = { none: '0', small: '2em', medium: '2.8em', large: '4em' };
export const namedSizes: Record<NodeSize, number> = {
  small: 0.85,
  medium: 1,
  large: 1.25,
  xlarge: 1.6
};
export const alignments = { start: 'flex-start', center: 'center', end: 'flex-end' };
export const justifications = {
  start: 'flex-start',
  center: 'center',
  end: 'flex-end',
  between: 'space-between',
  around: 'space-around',
  evenly: 'space-evenly'
};

// The page frame lays out at this logical width, with its height from the ratio, then scales to fit.
export const frameWidth = 1200;
export const frameRatios: Record<FrameRatio, number> = {
  '16:9': 16 / 9,
  '4:3': 4 / 3,
  '3:2': 3 / 2,
  '1:1': 1,
  '3:4': 3 / 4,
  '9:16': 9 / 16
};

/** A named scale value, or a number in em limited to 0–20. */
export function measure(
  scale: Record<string, string>,
  setting: string | number | undefined
): string | undefined {
  if (setting === undefined) return undefined;
  if (typeof setting !== 'number') return scale[setting];
  return Number.isFinite(setting) ? `${Math.min(Math.max(setting, 0), 20)}em` : undefined;
}
