import { describe, expect, it } from 'vitest';

import type { GlyphCluster } from '$lib/shared/visualization';
import { fragmentEmphasisBands } from './fragment-emphasis';

describe('fragmentEmphasisBands', () => {
  it('joins adjacent shaped clusters into one continuous phrase band', () => {
    expect(
      fragmentEmphasisBands([cluster(0, 0, 8), cluster(0, 11, 10), cluster(0, 23, 7)])
    ).toEqual([{ lineIndex: 0, rectX: 0, rectY: 2, rectWidth: 30, rectHeight: 10 }]);
  });

  it('keeps different lines and spatially separated visual runs distinct', () => {
    expect(fragmentEmphasisBands([cluster(1, 4, 8), cluster(0, 40, 8), cluster(0, 0, 8)])).toEqual([
      { lineIndex: 0, rectX: 0, rectY: 2, rectWidth: 8, rectHeight: 10 },
      { lineIndex: 0, rectX: 40, rectY: 2, rectWidth: 8, rectHeight: 10 },
      { lineIndex: 1, rectX: 4, rectY: 2, rectWidth: 8, rectHeight: 10 }
    ]);
  });
});

function cluster(line: number, x: number, width: number): GlyphCluster {
  return {
    clusterLineIndex: line,
    clusterSourceRange: { sourceRangeStart: x, sourceRangeEnd: x + 1 },
    clusterInkBounds: { rectX: x, rectY: 2, rectWidth: width, rectHeight: 10 }
  };
}
