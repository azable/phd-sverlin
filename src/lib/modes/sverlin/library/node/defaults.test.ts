import { describe, expect, it } from 'vitest';

import { keyedRandom } from '../../algorithm/random.server';
import { defaultsPolicy, drawDefaults as drawWith } from './defaults';

/** Draw the defaults for a seed with the same keyed randomness the compiler uses. */
const drawDefaults = (seed: number) => drawWith((key) => keyedRandom(seed, key));

describe('drawn Node defaults', () => {
  it('draws every default deterministically and within its policy', () => {
    const first = drawDefaults(42);
    expect(drawDefaults(42)).toEqual(first);
    for (const shape of ['box', 'card'] as const) {
      expect(defaultsPolicy[`${shape}.radius`].pick).toContain(first[shape].radius);
      expect(defaultsPolicy[`${shape}.strokeWidth`].pick).toContain(first[shape].strokeWidth);
      expect(defaultsPolicy[`${shape}.padding`].pick).toContain(first[shape].padding);
    }
    expect(defaultsPolicy['frame.justify'].pick).toContain(first.frame.justify);
    expect(defaultsPolicy['frame.align'].pick).toContain(first.frame.align);
    expect(defaultsPolicy.gap.pick).toContain(first.gap);
    expect(defaultsPolicy.font.pick).toContain(first.font);
  });

  it('draws pale HSL tints within their ranges, sometimes the plain surface', () => {
    const fills = Array.from({ length: 200 }, (_, seed) => drawDefaults(seed + 1).box);
    const plain = fills.filter(({ fill }) => fill === 'var(--sv-surface)');
    expect(plain.length).toBeGreaterThan(20);
    expect(plain.length).toBeLessThan(80);
    const tinted = fills.filter(({ fill }) => fill.startsWith('hsl('));
    const hues = new Set<number>();
    for (const { fill, stroke } of tinted) {
      const [hue, saturation, lightness] = fill.match(/[\d.]+/g)!.map(Number);
      const [strokeHue, , strokeLightness] = stroke.match(/[\d.]+/g)!.map(Number);
      expect(saturation).toBeGreaterThanOrEqual(15);
      expect(saturation).toBeLessThanOrEqual(40);
      expect(lightness).toBeGreaterThanOrEqual(93);
      expect(strokeLightness).toBeLessThanOrEqual(82);
      expect(strokeHue).toBe(hue);
      hues.add(Math.floor(hue / 60));
    }
    expect(hues.size).toBe(6);
  });

  it('sometimes draws no stroke for nodes that leave theirs unset', () => {
    const widths = Array.from({ length: 60 }, (_, seed) => drawDefaults(seed + 1).box.strokeWidth);
    expect(new Set(widths)).toEqual(new Set(['none', 'thin', 'thick']));
  });

  it('keys each default independently of the others', () => {
    const a = drawDefaults(7);
    const b = drawDefaults(8);
    expect(a).not.toEqual(b);
    // The box and card draws use different keys even though they share a policy shape.
    const seeds = Array.from({ length: 50 }, (_, seed) => drawDefaults(seed + 1));
    expect(seeds.some(({ box, card }) => box.fill !== card.fill)).toBe(true);
  });
});
