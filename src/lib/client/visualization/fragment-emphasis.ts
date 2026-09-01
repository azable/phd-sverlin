import type { GlyphCluster, LayoutRect } from '$lib/shared/visualization';

/** One continuous visual band behind spatially adjacent active glyphs. */
export type FragmentEmphasisBand = LayoutRect & { lineIndex: number };

/**
 * Merge the font renderer's per-cluster ink boxes into visual runs. A half-em
 * gap (estimated from the smaller ink height) bridges an ordinary word space
 * without joining genuinely separate or bidirectional runs.
 */
export function fragmentEmphasisBands(clusters: readonly GlyphCluster[]): FragmentEmphasisBand[] {
  const ordered = clusters.toSorted(
    (left, right) =>
      left.clusterLineIndex - right.clusterLineIndex ||
      left.clusterInkBounds.rectX - right.clusterInkBounds.rectX
  );
  const bands: FragmentEmphasisBand[] = [];

  for (const cluster of ordered) {
    const bounds = cluster.clusterInkBounds;
    const previous = bands.at(-1);
    if (previous && canMerge(previous, cluster)) {
      const right = Math.max(previous.rectX + previous.rectWidth, bounds.rectX + bounds.rectWidth);
      const bottom = Math.max(
        previous.rectY + previous.rectHeight,
        bounds.rectY + bounds.rectHeight
      );
      previous.rectX = Math.min(previous.rectX, bounds.rectX);
      previous.rectY = Math.min(previous.rectY, bounds.rectY);
      previous.rectWidth = right - previous.rectX;
      previous.rectHeight = bottom - previous.rectY;
    } else {
      bands.push({
        lineIndex: cluster.clusterLineIndex,
        rectX: bounds.rectX,
        rectY: bounds.rectY,
        rectWidth: bounds.rectWidth,
        rectHeight: bounds.rectHeight
      });
    }
  }

  return bands;
}

function canMerge(band: FragmentEmphasisBand, cluster: GlyphCluster): boolean {
  if (band.lineIndex !== cluster.clusterLineIndex) return false;
  const bounds = cluster.clusterInkBounds;
  const gap = bounds.rectX - (band.rectX + band.rectWidth);
  const bridge = Math.max(1, Math.min(band.rectHeight, bounds.rectHeight) * 0.5);
  return gap <= bridge;
}
