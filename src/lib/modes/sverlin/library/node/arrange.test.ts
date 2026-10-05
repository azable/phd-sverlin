import { describe, expect, it } from 'vitest';

import {
  arrange,
  keyedRandom,
  type ArrangeBox,
  type ArrangeOptions,
  type ArrangeResult
} from './arrange';

const boxes: ArrangeBox[] = [
  { key: 'a', width: 40, height: 40 },
  { key: 'b', width: 40, height: 40 },
  { key: 'c', width: 40, height: 40 },
  { key: 'head', width: 36, height: 20 },
  { key: 'note', width: 150, height: 32 }
];
const options: ArrangeOptions = {
  template: 'free',
  links: ['a -> b', 'b -> c', 'head -> a'],
  constraints: ['head above a', 'note below b', 'c rightOf b'],
  flow: 'x',
  gap: 12
};

function rect(result: ArrangeResult, key: string) {
  const index = boxes.findIndex((box) => box.key === key);
  const { x, y } = result.placements[index];
  const { width, height } = boxes[index];
  return {
    left: x,
    top: y,
    right: x + width,
    bottom: y + height,
    cx: x + width / 2,
    cy: y + height / 2
  };
}

describe('constraint arrangement', () => {
  const result = arrange(boxes, { ...options, random: keyedRandom(1, 'diagram') });

  it('places related nodes directly above, below, or beside each other, a gap apart', () => {
    const [a, b, c, head, note] = ['a', 'b', 'c', 'head', 'note'].map((key) => rect(result, key));
    expect(head.bottom + 12).toBeLessThanOrEqual(a.top + 0.5);
    expect(Math.abs(head.cx - a.cx)).toBeLessThan(0.5);
    expect(note.top).toBeGreaterThanOrEqual(b.bottom + 12 - 0.5);
    expect(Math.abs(note.cx - b.cx)).toBeLessThan(0.5);
    expect(c.left).toBeGreaterThanOrEqual(b.right + 12 - 0.5);
    expect(Math.abs(c.cy - b.cy)).toBeLessThan(0.5);
    expect(result.problems).toEqual([]);
  });

  it('keeps every node clear of the others and measures the whole', () => {
    const rects = boxes.map(({ key }) => rect(result, key));
    for (const [i, first] of rects.entries())
      for (const second of rects.slice(i + 1))
        expect(
          first.right <= second.left + 0.5 ||
            second.right <= first.left + 0.5 ||
            first.bottom <= second.top + 0.5 ||
            second.bottom <= first.top + 0.5
        ).toBe(true);
    expect(Math.min(...rects.map(({ left }) => left))).toBeCloseTo(0);
    expect(Math.min(...rects.map(({ top }) => top))).toBeCloseTo(0);
    expect(result.width).toBeCloseTo(Math.max(...rects.map(({ right }) => right)));
    expect(result.edges).toHaveLength(3);
    expect(result.edges.every(({ directed }) => directed)).toBe(true);
  });

  it('repeats a layout for a seed and varies it between seeds', () => {
    const again = arrange(boxes, { ...options, random: keyedRandom(1, 'diagram') });
    expect(again.placements).toEqual(result.placements);
    const others = [2, 3, 4].map(
      (seed) => arrange(boxes, { ...options, random: keyedRandom(seed, 'diagram') }).placements
    );
    expect(
      others.some((placements) => JSON.stringify(placements) !== JSON.stringify(result.placements))
    ).toBe(true);
  });

  it('reports links and relations it cannot use, and lays out the rest', () => {
    const partial = arrange(boxes, {
      template: 'free',
      links: ['a -> missing', 'a => b'],
      constraints: ['a near b', 'a below'],
      gap: 12
    });
    expect(partial.problems).toEqual([
      '"a -> missing" names no node with key "missing".',
      '"a => b" is not a link such as "a -> b".',
      '"a near b" is not a relation such as "a below b" (above, below, leftOf, rightOf, sameRow, sameColumn).',
      '"a below" is not a relation such as "a below b" (above, below, leftOf, rightOf, sameRow, sameColumn).'
    ]);
    expect(partial.placements).toHaveLength(boxes.length);
  });
});

describe('arrangement templates', () => {
  const overlaps = (result: ArrangeResult) =>
    boxes.some((first, i) =>
      boxes.slice(i + 1).some((second, offset) => {
        const [a, b] = [rect(result, first.key), rect(result, second.key)];
        void offset;
        return (
          a.left < b.right - 0.5 &&
          b.left < a.right - 0.5 &&
          a.top < b.bottom - 0.5 &&
          b.top < a.bottom - 0.5
        );
      })
    );

  it('lays a row out in order a gap apart, lined up across it', () => {
    const row = [
      { key: 'a', width: 40, height: 40 },
      { key: 'b', width: 30, height: 20 },
      { key: 'c', width: 50, height: 30 }
    ];
    const tops = (align: 'start' | 'end') => {
      const { placements } = arrange(row, { template: 'row', align, gap: 10 });
      expect(placements[1].x - placements[0].x).toBeCloseTo(50, 0);
      expect(placements[2].x - placements[1].x).toBeCloseTo(40, 0);
      return placements.map(({ y }, i) => (align === 'start' ? y : y + row[i].height));
    };
    for (const align of ['start', 'end'] as const) {
      const edges = tops(align);
      expect(edges.every((edge) => Math.abs(edge - edges[0]) < 0.5)).toBe(true);
    }
  });

  it('gathers unlinked children compactly in a free arrangement, varying with the seed', () => {
    const free = (seed: number) =>
      arrange(boxes, { template: 'free', gap: 10, random: keyedRandom(seed, 'frame') });
    const first = free(1);
    expect(overlaps(first)).toBe(false);
    // Together the boxes cover about 9000 square pixels; a compact arrangement stays near that.
    expect(first.width * first.height).toBeLessThan(60_000);
    const layouts = [1, 2, 3, 4, 5].map((seed) => JSON.stringify(free(seed).placements));
    expect(new Set(layouts).size).toBeGreaterThan(1);
  });
});
