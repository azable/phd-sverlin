/**
 * Constraint layout for a node's children with WebCola. Every arrangement is a set of constraints
 * over the children's measured boxes: a row lines them up on one horizontal line in order, a gap
 * apart; a column does the same vertically; free placement only keeps them clear of each other.
 * Links and relations such as "note below cells" add to any of these. Free layouts start from the
 * presentation's seed, so each presentation settles into its own arrangement, and the same seed
 * always gives the same one.
 */

import { Layout } from 'webcola/dist/src/layout';

/** One child to place: its key and its size in pixels. */
export type ArrangeBox = { key: string; width: number; height: number };

/** A child's top-left corner, relative to the arrangement's top-left. */
export type Placement = { key: string; x: number; y: number };

/** A link from one child's edge to another's, drawn with an arrowhead if directed. */
export type ArrangeEdge = { x1: number; y1: number; x2: number; y2: number; directed: boolean };

export type ArrangeResult = {
  placements: Placement[];
  edges: ArrangeEdge[];
  /** The size that hugs every child. */
  width: number;
  height: number;
  /** Links and constraints that were ignored, with why. */
  problems: string[];
  /** Each child's centre where the solver left it, by key, to start a later layout from. */
  centres: Record<string, Point>;
  /** The top-left of everything placed, in the solver's coordinates. */
  origin: Point;
};

export type Point = { x: number; y: number };

/** The arrangements the solver places: free, or a row or column with links or relations. */
export type Template = 'free' | 'row' | 'column';

export type ArrangeOptions = {
  template: Template;
  /** How a row's or column's children line up across it. */
  align?: 'start' | 'center' | 'end';
  /** Links such as 'a -> b' (directed) or 'a - b'. */
  links?: readonly string[];
  /**
   * Relations such as 'a below b' (directly below, centred, a gap away), 'a rightOf b', or
   * 'a sameRow b' (centred on one horizontal line, in either order).
   */
  constraints?: readonly string[];
  /** The axis directed links point along in a free arrangement: 'x' or 'y'. */
  flow?: 'x' | 'y';
  /** The space between children, in pixels. */
  gap: number;
  /** A random number in [0, 1) for a key, or undefined to start every child at the centre. */
  random?: (key: string) => number;
  /**
   * Centres to start children from, by key, such as where the previous step left them: a warm start
   * keeps whatever has not changed in place. Children without one start from `random`.
   */
  starts?: Readonly<Record<string, Point>>;
  /**
   * Children to hold at their start, such as those unchanged since the previous step, so only what
   * changed moves.
   */
  still?: ReadonlySet<string>;
  /**
   * Where links attach, by key, when not to a whole child: a node inside a child, such as the
   * value cell of a column that also holds labels.
   */
  anchors?: Readonly<Record<string, Anchor>>;
};

/** A box a link attaches to: inside child `box`, relative to that child's top-left. */
export type Anchor = { box: number; x: number; y: number; width: number; height: number };

// The least room left for an arrow between the boxes it joins, so it is always visible.
const arrowRoom = 28;

const relations = ['above', 'below', 'leftOf', 'rightOf', 'sameRow', 'sameColumn'] as const;
type Relation = (typeof relations)[number];

// The area starting positions are spread over; only its proportions matter.
const startArea = { width: 800, height: 500 };

type Separation = { axis: 'x' | 'y'; left: number; right: number; gap: number; equality?: true };
type Alignment = {
  type: 'alignment';
  axis: 'x' | 'y';
  offsets: { node: number; offset: number }[];
};

export function arrange(boxes: readonly ArrangeBox[], options: ArrangeOptions): ArrangeResult {
  const problems: string[] = [];
  const index = new Map(boxes.map((box, position) => [box.key, position]));
  const at = (key: string, source: string) => {
    const position = index.get(key);
    if (position === undefined) problems.push(`"${source}" names no node with key "${key}".`);
    return position;
  };
  // A link's end: a keyed anchor inside a child, or a whole keyed child.
  const anchorOf = (key: string, source: string): Anchor | undefined => {
    const anchor = options.anchors?.[key];
    if (anchor) return anchor;
    const box = at(key, source);
    return box === undefined
      ? undefined
      : { box, x: 0, y: 0, width: boxes[box].width, height: boxes[box].height };
  };
  const extent = (axis: 'x' | 'y') => (axis === 'x' ? 'width' : 'height');
  // How far an anchor's centre lies from its child's centre along an axis.
  const offsetOf = (anchor: Anchor, axis: 'x' | 'y') =>
    axis === 'x'
      ? anchor.x + anchor.width / 2 - boxes[anchor.box].width / 2
      : anchor.y + anchor.height / 2 - boxes[anchor.box].height / 2;
  // Box centres a gap apart along an axis, exactly.
  const apart = (axis: 'x' | 'y', left: number, right: number): Separation => ({
    axis,
    left,
    right,
    gap: (boxes[left][extent(axis)] + boxes[right][extent(axis)]) / 2 + options.gap,
    equality: true
  });
  const aligned = (axis: 'x' | 'y', nodes: number[], edge = 'center'): Alignment => ({
    type: 'alignment',
    axis,
    // WebCola places each node's centre at the first node's plus its offset, so half the difference
    // in size lines up starts (or, negated, ends) instead of centres.
    offsets: nodes.map((node) => ({
      node,
      offset:
        edge === 'center'
          ? 0
          : ((edge === 'start' ? 1 : -1) *
              (boxes[node][extent(axis)] - boxes[nodes[0]][extent(axis)])) /
            2
    }))
  });

  // A row or column is its children in order along one axis, lined up across it.
  const template: (Separation | Alignment)[] = [];
  if (options.template !== 'free' && boxes.length) {
    const along = options.template === 'row' ? 'x' : 'y';
    for (let i = 0; i + 1 < boxes.length; i++) template.push(apart(along, i, i + 1));
    template.push(
      aligned(
        along === 'x' ? 'y' : 'x',
        boxes.map((_, i) => i),
        options.align ?? 'center'
      )
    );
  }

  const links = (options.links ?? []).flatMap((text) => {
    const match = /^\s*(\S+)\s*(->|-)\s*(\S+)\s*$/u.exec(text);
    if (!match) {
      problems.push(`"${text}" is not a link such as "a -> b".`);
      return [];
    }
    const from = anchorOf(match[1], text);
    const to = anchorOf(match[3], text);
    return !from || !to || from.box === to.box
      ? []
      : [{ source: from.box, target: to.box, from, to, directed: match[2] === '->' }];
  });

  const related = (options.constraints ?? []).flatMap((text) => {
    const match = /^\s*(\S+)\s+(\S+)\s+(\S+)\s*$/u.exec(text);
    const relation = match?.[2] as Relation | undefined;
    if (!match || !relation || !relations.includes(relation)) {
      problems.push(`"${text}" is not a relation such as "a below b" (${relations.join(', ')}).`);
      return [];
    }
    const a = at(match[1], text);
    const b = at(match[3], text);
    return a === undefined || b === undefined || a === b ? [] : [{ a, b, relation }];
  });
  const constraints = related.flatMap(({ a, b, relation }): (Separation | Alignment)[] => {
    if (relation === 'sameRow' || relation === 'sameColumn')
      return [aligned(relation === 'sameRow' ? 'y' : 'x', [a, b])];
    // "a above b" means directly above, a gap away: exactly apart along one axis, centred on the
    // other, so labels and captions sit by what they describe.
    const axis = relation === 'above' || relation === 'below' ? 'y' : 'x';
    const [left, right] = relation === 'below' || relation === 'rightOf' ? [b, a] : [a, b];
    return [apart(axis, left, right), aligned(axis === 'y' ? 'x' : 'y', [a, b])];
  });

  // Each link's length comes from its own two boxes: half of each plus room for the arrow. With a
  // flow, a directed link's target sits that far along the flow axis, so arrows run along it,
  // except between boxes a relation already places across the flow (such as a label above).
  const flowExtent = options.flow === 'y' ? 'height' : 'width';
  const across = new Set(
    related.flatMap(({ a, b, relation }) => {
      const crossing =
        options.flow === 'y'
          ? ['leftOf', 'rightOf', 'sameRow'].includes(relation)
          : ['above', 'below', 'sameColumn'].includes(relation);
      return crossing ? [`${a} ${b}`, `${b} ${a}`] : [];
    })
  );
  const room = Math.max(3 * options.gap, arrowRoom);
  const laidLinks = links.map(({ source, target, from, to, directed }) => {
    const along = (from[flowExtent] + to[flowExtent]) / 2 + room;
    const ideal = options.flow
      ? along
      : (Math.max(from.width, from.height) + Math.max(to.width, to.height)) / 2 + room;
    const placed = across.has(`${source} ${target}`);
    return { source, target, from, to, ideal, along, directed, placed };
  });
  // A link between boxes a relation already places is drawn but not laid out; otherwise its graph
  // distances would pull the rest askew.
  const solvedLinks: { source: number; target: number; ideal: number }[] = laidLinks.filter(
    ({ placed }) => !placed
  );

  // Along a flow, each directed link's target anchor sits at least a link's length further along
  // than its source anchor, so arrows run with the flow. A link that closes a cycle cannot point
  // forward too, so it is left free; and links forming a simple chain (one out, one in) are lined
  // up on their anchors, so a list runs straight.
  const flowing: (Separation | Alignment)[] = [];
  if (options.flow && options.template === 'free') {
    const axis = options.flow;
    const cross = axis === 'x' ? 'y' : 'x';
    const forward = laidLinks.filter(
      ({ directed, placed }, i) => directed && !placed && !closesCycle(laidLinks, i)
    );
    const outs = new Map<number, number>();
    const ins = new Map<number, number>();
    for (const { source, target } of forward) {
      outs.set(source, (outs.get(source) ?? 0) + 1);
      ins.set(target, (ins.get(target) ?? 0) + 1);
    }
    for (const { source, target, from, to, along } of forward) {
      flowing.push({
        axis,
        left: source,
        right: target,
        gap: along + offsetOf(from, axis) - offsetOf(to, axis)
      });
      if (outs.get(source) === 1 && ins.get(target) === 1)
        flowing.push({
          type: 'alignment',
          axis: cross,
          offsets: [
            { node: source, offset: 0 },
            { node: target, offset: offsetOf(from, cross) - offsetOf(to, cross) }
          ]
        });
    }
  }

  // A warm start, from where children were before, keeps them there; a child new to it starts near
  // the others, by an amount the seed varies, instead of anywhere in the start area.
  const known = boxes.flatMap((box) => options.starts?.[box.key] ?? []);
  const warm = known.length > 0;
  const middle = warm
    ? {
        x: known.reduce((sum, { x }) => sum + x, 0) / known.length,
        y: known.reduce((sum, { y }) => sum + y, 0) / known.length
      }
    : { x: startArea.width / 2, y: startArea.height / 2 };
  const nodes: { width: number; height: number; x?: number; y?: number; fixed?: number }[] =
    boxes.map((box) => ({
      // The gap is added to each box, so overlap removal keeps boxes that far apart.
      width: box.width + options.gap,
      height: box.height + options.gap,
      ...(options.still?.has(box.key) && options.starts?.[box.key] ? { fixed: 1 } : {}),
      ...(options.starts?.[box.key] ??
        (options.random
          ? warm
            ? {
                x: middle.x + (options.random(`${box.key}.x`) - 0.5) * box.width,
                y: middle.y + (options.random(`${box.key}.y`) - 0.5) * box.height
              }
            : {
                x: options.random(`${box.key}.x`) * startArea.width,
                y: options.random(`${box.key}.y`) * startArea.height
              }
          : {}))
    }));

  // Nothing pulls separate groups together (children joined by links or relations count as one), so
  // in a free arrangement one child of each group is tied to an invisible hub: they gather round it
  // compactly, in an order that depends on where the seed starts them.
  const leaders = groupLeaders(boxes.length, [
    ...solvedLinks,
    ...related.map(({ a, b }) => ({ source: a, target: b }))
  ]);
  if (options.template === 'free' && leaders.length > 1) {
    const hub = nodes.length;
    nodes.push({
      width: 0.01,
      height: 0.01,
      ...(warm || options.random ? middle : {})
    });
    for (const member of leaders) {
      const { width, height } = boxes[member];
      solvedLinks.push({
        source: hub,
        target: member,
        ideal: Math.max(width, height) / 2 + options.gap
      });
    }
  }

  if (boxes.length) {
    const layout = new Layout()
      .size([startArea.width, startArea.height])
      .nodes(nodes)
      .links(solvedLinks)
      .constraints([...template, ...constraints, ...flowing])
      .avoidOverlaps(true)
      .handleDisconnected(false)
      .linkDistance((link) => (link as unknown as { ideal: number }).ideal);
    // Iterations without constraints, then with the view's, then with all; running on to
    // convergence is synchronous here, and the same input always gives the same result. A warm
    // start skips the unconstrained iterations, which would scatter what is already in place.
    layout.start(warm ? 0 : 20, 20, 20, 0, true, false);
  }

  const centres = nodes.slice(0, boxes.length).map(({ x = 0, y = 0 }) => ({ x, y }));
  // Placements are relative to the top-left of everything placed.
  const left = Math.min(...boxes.map((box, i) => centres[i].x - box.width / 2));
  const top = Math.min(...boxes.map((box, i) => centres[i].y - box.height / 2));
  const placements = boxes.map((box, i) => ({
    key: box.key,
    x: centres[i].x - box.width / 2 - left,
    y: centres[i].y - box.height / 2 - top
  }));
  const width = Math.max(0, ...boxes.map((box, i) => placements[i].x + box.width));
  const height = Math.max(0, ...boxes.map((box, i) => placements[i].y + box.height));

  // Arrows run between anchors, from edge to edge.
  const edges = links.map(({ from: tail, to: head, directed }) => {
    const from = anchorRect(tail, placements[tail.box]);
    const to = anchorRect(head, placements[head.box]);
    const start = edgePoint(from, to.cx, to.cy);
    const end = edgePoint(to, from.cx, from.cy);
    return { x1: start.x, y1: start.y, x2: end.x, y2: end.y, directed };
  });

  return {
    placements,
    edges,
    width,
    height,
    problems,
    centres: Object.fromEntries(boxes.map((box, i) => [box.key, centres[i]])),
    origin: { x: left, y: top }
  };
}

/** One child from each group the links connect, counting an unlinked child as its own group. */
function groupLeaders(count: number, links: readonly { source: number; target: number }[]) {
  const parent = Array.from({ length: count }, (_, i) => i);
  const root = (i: number): number => (parent[i] === i ? i : (parent[i] = root(parent[i])));
  for (const { source, target } of links)
    if (source < count && target < count) parent[root(source)] = root(target);
  return [...new Set(parent.map((_, i) => root(i)))];
}

type Rect = { cx: number; cy: number; halfWidth: number; halfHeight: number };

function anchorRect(anchor: Anchor, placement: Placement): Rect {
  return {
    cx: placement.x + anchor.x + anchor.width / 2,
    cy: placement.y + anchor.y + anchor.height / 2,
    halfWidth: anchor.width / 2,
    halfHeight: anchor.height / 2
  };
}

/** Whether directed link i returns to its source along earlier directed links, closing a cycle. */
function closesCycle(
  links: readonly { source: number; target: number; directed: boolean; placed: boolean }[],
  i: number
): boolean {
  const next = new Map<number, number[]>();
  for (const { source, target, directed, placed } of links.slice(0, i))
    if (directed && !placed) next.set(source, [...(next.get(source) ?? []), target]);
  const seen = new Set<number>();
  const stack = [links[i].target];
  while (stack.length) {
    const at = stack.pop() as number;
    if (at === links[i].source) return true;
    if (seen.has(at)) continue;
    seen.add(at);
    stack.push(...(next.get(at) ?? []));
  }
  return false;
}

/** Where the line from a box's centre towards a point leaves the box. */
function edgePoint(rect: Rect, towardX: number, towardY: number): { x: number; y: number } {
  const dx = towardX - rect.cx;
  const dy = towardY - rect.cy;
  if (dx === 0 && dy === 0) return { x: rect.cx, y: rect.cy };
  const scale = Math.min(
    dx === 0 ? Infinity : rect.halfWidth / Math.abs(dx),
    dy === 0 ? Infinity : rect.halfHeight / Math.abs(dy)
  );
  return { x: rect.cx + dx * scale, y: rect.cy + dy * scale };
}

/**
 * A random number in [0, 1) for each key, fixed by a seed and a scope (such as a node's id):
 * FNV-1a over the three, finished with mulberry32.
 */
export function keyedRandom(seed: number, scope: string): (key: string) => number {
  return (key) => {
    let hash = 0x811c9dc5;
    for (const character of `${seed}:${scope}:${key}`)
      hash = Math.imul(hash ^ character.charCodeAt(0), 0x01000193);
    let state = (hash + 0x6d2b79f5) | 0;
    state = Math.imul(state ^ (state >>> 15), state | 1);
    state ^= state + Math.imul(state ^ (state >>> 7), state | 61);
    return ((state ^ (state >>> 14)) >>> 0) / 4294967296;
  };
}
