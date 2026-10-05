/**
 * Shapes for chains of links, such as a linked list, and curved arrows between placed boxes. A free
 * arrangement whose links form a chain or a cycle lays it out in one of several shapes, drawn from
 * the seed unless the view names one, sized to the space it has; arrows are cubic curves that bend
 * round other boxes and labels. Every choice is the seed's, so presentations differ in look while
 * showing the same structure.
 */

/** The shapes a chain of links can take. */
export const chainShapes = ['line', 'snake', 'wave', 'arc', 'ring', 'scatter'] as const;
export type ChainShape = (typeof chainShapes)[number];

type Point = { x: number; y: number };
type Size = { width: number; height: number };

/**
 * The longest chain the directed links form, following each node's one link out from a node with
 * none in, or, if every node in it has one link in, the cycle they form. Nodes with several links
 * out or in end a chain there, so trees and graphs are left to the general layout.
 */
export function findChain(
  count: number,
  links: readonly { source: number; target: number }[]
): { nodes: number[]; cycle: boolean } | undefined {
  const next = new Map<number, number>();
  const ins = new Map<number, number>();
  const outs = new Map<number, number>();
  for (const { source, target } of links) {
    if (source >= count || target >= count) continue;
    outs.set(source, (outs.get(source) ?? 0) + 1);
    ins.set(target, (ins.get(target) ?? 0) + 1);
    next.set(source, target);
  }
  const simple = (node: number) => (outs.get(node) ?? 0) <= 1 && (ins.get(node) ?? 0) <= 1;
  let best: { nodes: number[]; cycle: boolean } | undefined;
  for (let start = 0; start < count; start++) {
    if (!outs.get(start) || !simple(start)) continue;
    const opening = !ins.get(start);
    const nodes = [start];
    let cycle = false;
    for (let at = next.get(start); at !== undefined && simple(at); at = next.get(at)) {
      if (at === start) {
        cycle = true;
        break;
      }
      if (nodes.includes(at)) break;
      nodes.push(at);
      if (!outs.get(at)) break;
    }
    // A chain is read from its first node; a cycle may start anywhere, so the lowest is used.
    if (!opening && !cycle) continue;
    if (cycle && nodes.some((node) => node < start)) continue;
    if (!best || nodes.length > best.nodes.length) best = { nodes, cycle };
  }
  return best && best.nodes.length >= 3 ? best : undefined;
}

/**
 * Centres for a chain's nodes in a shape, along the x axis, for a space of the given width to
 * height. `random` varies each shape's free parameters, such as a wave's height or an arc's sweep.
 */
export function chainCentres(
  shape: ChainShape,
  sizes: readonly Size[],
  options: { room: number; aspect: number; cycle: boolean; random: (key: string) => number }
): Point[] {
  return stretched(shapeCentres(shape, sizes, options), sizes, options.aspect);
}

// How far a shape may be spread along one axis to match its space, so it stays recognisable.
const largestStretch = 2.5;

/**
 * A shape spread along whichever axis falls short of the space's proportions, by up to
 * largestStretch, so it fills the space rather than leaving it empty on one side.
 */
function stretched(centres: Point[], sizes: readonly Size[], aspect: number): Point[] {
  const { width, height } = extentOf(centres, sizes);
  const ratio = width / Math.max(1, height);
  // Near enough already; a slight stretch would only distort the shape.
  if (Math.abs(Math.log(ratio / aspect)) < Math.log(1.15)) return centres;
  const mean = {
    x: centres.reduce((sum, { x }) => sum + x, 0) / centres.length,
    y: centres.reduce((sum, { y }) => sum + y, 0) / centres.length
  };
  const [sx, sy] =
    ratio < aspect
      ? [Math.min(largestStretch, aspect / ratio), 1]
      : [1, Math.min(largestStretch, ratio / aspect)];
  return centres.map(({ x, y }) => ({
    x: mean.x + (x - mean.x) * sx,
    y: mean.y + (y - mean.y) * sy
  }));
}

function shapeCentres(
  shape: ChainShape,
  sizes: readonly Size[],
  options: { room: number; aspect: number; cycle: boolean; random: (key: string) => number }
): Point[] {
  const count = sizes.length;
  // One step along the chain fits the widest node and room for an arrow; rows sit far enough apart
  // for the tallest node and an arrow turning between them.
  const across = Math.max(...sizes.map(({ width }) => width)) + options.room;
  const down = Math.max(...sizes.map(({ height }) => height)) + options.room;
  const pick = (key: string, low: number, high: number) => low + options.random(key) * (high - low);
  switch (shape) {
    case 'line':
      return sizes.map((_, i) => ({ x: i * across, y: 0 }));
    case 'snake': {
      // As many rows as bring the chain closest to the space's shape, read back and forth.
      let rows = 1;
      let closest = Infinity;
      for (let candidate = 1; candidate <= count; candidate++) {
        const columns = Math.ceil(count / candidate);
        const mismatch = Math.abs(
          Math.log((columns * across) / (candidate * down * 1.25) / options.aspect)
        );
        if (mismatch < closest) [rows, closest] = [candidate, mismatch];
      }
      const columns = Math.ceil(count / rows);
      return sizes.map((_, i) => {
        const row = Math.floor(i / columns);
        const column = row % 2 ? columns - 1 - (i % columns) : i % columns;
        return { x: column * across, y: row * down * 1.25 };
      });
    }
    case 'wave': {
      // Alternately up and down, or along a smooth swell, by an amount the seed chooses.
      const height = down * pick('wave.height', 0.6, 1.3);
      const smooth = options.random('wave.smooth') < 0.5;
      return sizes.map((_, i) => ({
        x: i * across * 0.85,
        y: smooth ? height * Math.sin((i * Math.PI) / 2) : (i % 2) * height
      }));
    }
    case 'arc':
    case 'ring': {
      // A ring closes the circle; an arc sweeps part of one, bulging up or down.
      const ring = shape === 'ring' || options.cycle;
      const sweep = ring ? 2 * Math.PI : pick('arc.sweep', 0.6, 1.2) * Math.PI;
      const steps = ring ? count : count - 1;
      const radius = Math.max(across, (steps * across) / sweep);
      const start = ring ? options.random('ring.start') * 2 * Math.PI : -sweep / 2;
      const flip = !ring && options.random('arc.flip') < 0.5 ? -1 : 1;
      return sizes.map((_, i) => {
        const angle = start + (i * sweep) / steps;
        return { x: radius * Math.sin(angle), y: -flip * radius * Math.cos(angle) };
      });
    }
    case 'scatter': {
      // Free positions that keep each node near the next: a walk over a grid of the space's
      // proportions, by rows, by columns, or spiralling inwards, as the seed chooses, with each node
      // nudged within its cell. The cells leave room for arrows to curve.
      const cell = { x: across * 1.35, y: down * 1.5 };
      let rows = 1;
      let closest = Infinity;
      for (let candidate = 1; candidate <= count; candidate++) {
        const columns = Math.ceil(count / candidate);
        const mismatch = Math.abs(
          Math.log((columns * cell.x) / (candidate * cell.y) / options.aspect)
        );
        if (mismatch < closest) [rows, closest] = [candidate, mismatch];
      }
      const columns = Math.ceil(count / rows);
      const walk = ['rows', 'columns', 'spiral'][Math.floor(options.random('scatter.walk') * 3)];
      const cells: Point[] = [];
      if (walk === 'spiral')
        for (let ring = 0; cells.length < rows * columns; ring++) {
          const [left, top, right, bottom] = [ring, ring, columns - 1 - ring, rows - 1 - ring];
          for (let x = left; x <= right; x++) cells.push({ x, y: top });
          for (let y = top + 1; y <= bottom; y++) cells.push({ x: right, y });
          if (bottom > top) for (let x = right - 1; x >= left; x--) cells.push({ x, y: bottom });
          if (right > left) for (let y = bottom - 1; y > top; y--) cells.push({ x: left, y });
        }
      else
        for (let i = 0; i < rows * columns; i++) {
          // Back and forth along rows, or up and down columns.
          const major = walk === 'rows' ? columns : rows;
          const line = Math.floor(i / major);
          const step = line % 2 ? major - 1 - (i % major) : i % major;
          cells.push(walk === 'rows' ? { x: step, y: line } : { x: line, y: step });
        }
      return sizes.map((_, i) => ({
        x: (cells[i].x + (options.random(`scatter.${i}.x`) - 0.5) * 0.5) * cell.x,
        y: (cells[i].y + (options.random(`scatter.${i}.y`) - 0.5) * 0.5) * cell.y
      }));
    }
  }
}

/** The bounds a set of centres covers with boxes of these sizes. */
export function extentOf(centres: readonly Point[], sizes: readonly Size[]): Size {
  const left = Math.min(...centres.map(({ x }, i) => x - sizes[i].width / 2));
  const right = Math.max(...centres.map(({ x }, i) => x + sizes[i].width / 2));
  const top = Math.min(...centres.map(({ y }, i) => y - sizes[i].height / 2));
  const bottom = Math.max(...centres.map(({ y }, i) => y + sizes[i].height / 2));
  return { width: right - left, height: bottom - top };
}

/** A box on the page, by its edges. */
export type Box = { left: number; top: number; right: number; bottom: number };

/**
 * A cubic curve from one box to another that crosses as few obstacles as it can: it tries bends to
 * either side of the straight line, in an order the seed sets, and keeps the first that crosses
 * least. The curve leaves and meets the boxes at their edges.
 */
export function routeCurve(
  from: Box,
  to: Box,
  obstacles: readonly Box[],
  preference: readonly number[],
  ends: { from?: Surround; to?: Surround } = {}
): { path: string; start: Point; end: Point } {
  const centre = (box: Box) => ({ x: (box.left + box.right) / 2, y: (box.top + box.bottom) / 2 });
  const [p, q] = [centre(from), centre(to)];
  const distance = Math.hypot(q.x - p.x, q.y - p.y) || 1;
  const normal = { x: -(q.y - p.y) / distance, y: (q.x - p.x) / distance };
  let best: { path: string; start: Point; end: Point; hits: number } | undefined;
  for (const bend of preference) {
    const offset = { x: normal.x * bend * distance, y: normal.y * bend * distance };
    const c1 = { x: p.x + (q.x - p.x) / 3 + offset.x, y: p.y + (q.y - p.y) / 3 + offset.y };
    const c2 = {
      x: p.x + (2 * (q.x - p.x)) / 3 + offset.x,
      y: p.y + (2 * (q.y - p.y)) / 3 + offset.y
    };
    const start = endPoint(from, ends.from, c1);
    const end = endPoint(to, ends.to, c2);
    let hits = 0;
    for (let i = 1; i < 24; i++) {
      const point = cubicAt(start, c1, c2, end, i / 24);
      for (const box of obstacles)
        if (point.x > box.left && point.x < box.right && point.y > box.top && point.y < box.bottom)
          hits++;
    }
    if (!best || hits < best.hits) {
      const round = (value: number) => Math.round(value * 10) / 10;
      best = {
        path: `M${round(start.x)},${round(start.y)} C${round(c1.x)},${round(c1.y)} ${round(c2.x)},${round(c2.y)} ${round(end.x)},${round(end.y)}`,
        start,
        end,
        hits
      };
    }
    if (hits === 0) break;
  }
  const { path, start, end } = best as NonNullable<typeof best>;
  return { path, start, end };
}

function cubicAt(a: Point, b: Point, c: Point, d: Point, t: number): Point {
  const u = 1 - t;
  return {
    x: u * u * u * a.x + 3 * u * u * t * b.x + 3 * u * t * t * c.x + t * t * t * d.x,
    y: u * u * u * a.y + 3 * u * u * t * b.y + 3 * u * t * t * c.y + t * t * t * d.y
  };
}

/** Where the line from a box's centre towards a point leaves the box. */
function exitPoint(box: Box, toward: Point): Point {
  const cx = (box.left + box.right) / 2;
  const cy = (box.top + box.bottom) / 2;
  const dx = toward.x - cx;
  const dy = toward.y - cy;
  if (dx === 0 && dy === 0) return { x: cx, y: cy };
  const scale = Math.min(
    dx === 0 ? Infinity : (box.right - box.left) / 2 / Math.abs(dx),
    dy === 0 ? Infinity : (box.bottom - box.top) / 2 / Math.abs(dy)
  );
  return { x: cx + dx * Math.min(scale, 1), y: cy + dy * Math.min(scale, 1) };
}

/** The node around an arrow's end, when the end is a box inside it, and the node's other content. */
export type Surround = { outer: Box; parts: readonly Box[] };

/**
 * Where an arrow meets its end box, heading towards a point: at the box's edge, or, when the box sits
 * inside a node and the way out to the node's edge crosses the node's other content, such as another
 * field of a record, at the node's own edge instead, still in line with the box.
 */
function endPoint(box: Box, surround: Surround | undefined, toward: Point): Point {
  const inner = exitPoint(box, toward);
  if (!surround) return inner;
  const centre = { x: (box.left + box.right) / 2, y: (box.top + box.bottom) / 2 };
  const outer = exitFrom(surround.outer, centre, toward);
  for (let i = 1; i < 10; i++) {
    const t = i / 10;
    const point = { x: inner.x + (outer.x - inner.x) * t, y: inner.y + (outer.y - inner.y) * t };
    if (
      surround.parts.some(
        (part) =>
          point.x > part.left && point.x < part.right && point.y > part.top && point.y < part.bottom
      )
    )
      return outer;
  }
  return inner;
}

/** Where a ray from a point inside a box, towards another point, leaves the box. */
function exitFrom(box: Box, origin: Point, toward: Point): Point {
  const dx = toward.x - origin.x;
  const dy = toward.y - origin.y;
  const reach = Math.min(
    dx > 0 ? (box.right - origin.x) / dx : dx < 0 ? (box.left - origin.x) / dx : Infinity,
    dy > 0 ? (box.bottom - origin.y) / dy : dy < 0 ? (box.top - origin.y) / dy : Infinity
  );
  return Number.isFinite(reach) ? { x: origin.x + dx * reach, y: origin.y + dy * reach } : origin;
}
