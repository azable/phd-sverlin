import * as p from '@penrose/core';
import { tick } from 'svelte';
import { SvelteMap } from 'svelte/reactivity';

// const snapModulo = (x: p.Num, modulo: number, weight = 1): p.Num => {
//   return 0;
//   return p.mul(weight, p.pow(p.sin(p.div(p.mul(Math.PI, x), modulo)), 2));
// };

const lessThanWithPadding = (a: p.Num, b: p.Num, padding: p.Num): p.Num => {
  const gap = p.add(p.sub(a, b), padding);
  const violation = p.max(gap, 0);
  const penalty = p.pow(violation, 2);
  return penalty;
};

type Interval = {
  min: number;
  max: number;
};

type VariableInfo = {
  variable: p.Var;
  range: Interval;
};

export type NodeConfig = {
  style: Record<string, string | number>;
};

type ReactiveValue<T> = {
  value: T;
};

type StyleValue =
  | {
      type: 'variable';
      varId: string;
    }
  | {
      type: 'constant';
      value: number;
    }
  | {
      type: 'fixed';
      value: string;
    };

export type Node = {
  id: string;
  content?: NodeContent;
  constraints: SvelteMap<string, p.Num>;
  style: Record<string, StyleValue>;
  localUniqId: (suffix: string) => string;
  setContent: (content: string) => Node;
};

export type NodeView = {
  nodeId: string;
  style: Record<string, string>;
  content?: NodeContent;
};

type NodeContent = {
  text: ReactiveValue<string>;
  clientWidth: ReactiveValue<number>;
  clientHeight: ReactiveValue<number>;
};

const parseVariableName = (name: string): string => {
  if (!name) {
    throw new Error(`Variable name cannot be empty`);
  }
  // ensure all lowercase and underscores/dashes only
  if (!/^[a-z_][a-z0-9_-]*$/.test(name)) {
    throw new Error(`Invalid variable name: ${name}`);
  }
  return name;
};

const toCSSrule = (key: string, value: number | string): [string, string] => {
  const kebabKey = key.replace(/([a-z])([A-Z])/g, '$1-$2').toLowerCase();

  if (typeof value === 'string') {
    return [kebabKey, value];
  }

  const map: Record<string, (value: number) => string> = {
    backgroundColor: (v) => v.toString(),

    width: (v) => `${v}px`,
    height: (v) => `${v}px`,
    left: (v) => `${v}px`,
    top: (v) => `${v}px`,

    minWidth: (v) => `${v}px`,
    minHeight: (v) => `${v}px`,

    padding: (v) => `${v}px`,
    paddingTop: (v) => `${v}px`,
    paddingBottom: (v) => `${v}px`,
    paddingLeft: (v) => `${v}px`,
    paddingRight: (v) => `${v}px`,

    margin: (v) => `${v}px`,
    marginTop: (v) => `${v}px`,
    marginBottom: (v) => `${v}px`,
    marginLeft: (v) => `${v}px`,
    marginRight: (v) => `${v}px`,

    fontSize: (v) => `${v}px`,

    borderWidth: (v) => `${v}px`,
    borderRadius: (v) => `${v}px`,

    zIndex: (v) => v.toString()
  };

  if (key in map) {
    return [kebabKey, map[key](value)];
  }
  throw new Error(`No CSS mapping for key: ${key}`);
};

type LayoutConfig = {
  width?: number;
  height?: number;
  unitSize?: number;
};

export function createLayout(config: LayoutConfig = {}) {
  const { width: rootWidth, height: rootHeight, unitSize = 1 } = config;

  const roundToUnit = (value: number, f = Math.round): number => {
    return value;
    if (!unitSize) return value;
    return f(value / unitSize) * unitSize;
  };

  const nodes = $state({}) as Record<string, Node>;

  const constraints = new SvelteMap<string, p.Num>();
  const variables = {} as Record<string, VariableInfo>;

  const allConstraints = $derived.by<p.Num[]>(() => {
    const nodeConstraints = Object.values(nodes).flatMap((node) =>
      Object.values(node.constraints).map((constraint) => constraint)
    );
    return [...Array.from(constraints.values()), ...nodeConstraints];
  });

  const globals = {
    byName: (name: string) => `global-${name}`
  };

  const output = $state({
    views: [] as NodeView[]
  });

  const setConstraints = (newConstraints: Record<string, p.Num>) => {
    Object.entries(newConstraints).forEach(([key, constraint]) => {
      console.log(`Setting constraint ${key}:`, constraint);
      constraints.set(key, constraint);
    });
  };

  const num = (value: StyleValue | ReactiveValue<number> | number): p.Num => {
    if (typeof value === 'number') {
      return value;
    }

    if (typeof value === 'object' && 'value' in value) {
      return (value as ReactiveValue<number>).value;
    }

    const styleValue = value as StyleValue;

    if (styleValue.type === 'variable') {
      const varId = styleValue.varId;
      if (varId in variables) {
        return variables[varId].variable;
      } else {
        throw new Error(`Variable ${varId} not found`);
      }
    }

    if (styleValue.type === 'constant') {
      return styleValue.value as p.Num;
    }
    throw new Error(`Cannot convert ${styleValue.type} to number`);
  };

  const bounds = (node: Node) => {
    console.log(node.style);
    const left = num(node.style.left);
    const top = num(node.style.top);
    const width = num(node.style.width);
    const height = num(node.style.height);
    const right = p.add(left, width);
    const bottom = p.add(top, height);

    return { left, top, right, bottom, width, height };
  };

  const constraint = {
    // Ensure node A is fully contained within node B
    contains: (containerNode: Node, node: Node) => {
      const { left: cLeft, top: cTop, right: cRight, bottom: cBottom } = bounds(containerNode);
      const { left, top, right, bottom } = bounds(node);

      setConstraints({
        [containerNode.localUniqId(`contains-${node.localUniqId('left')}`)]: lessThanWithPadding(
          cLeft,
          left,
          0
        ),
        [containerNode.localUniqId(`contains-${node.localUniqId('right')}`)]: lessThanWithPadding(
          right,
          cRight,
          0
        ),
        [containerNode.localUniqId(`contains-${node.localUniqId('top')}`)]: lessThanWithPadding(
          cTop,
          top,
          0
        ),
        [containerNode.localUniqId(`contains-${node.localUniqId('bottom')}`)]: lessThanWithPadding(
          bottom,
          cBottom,
          0
        )
      });
    },

    // Ensure nodes A and B do not overlap
    disjoint: (nodeA: Node, nodeB: Node) => {
      const {
        left: aLeft,
        top: aTop,
        right: aRight,
        bottom: aBottom,
        width: aWidth,
        height: aHeight
      } = bounds(nodeA);
      const {
        left: bLeft,
        top: bTop,
        right: bRight,
        bottom: bBottom,
        width: bWidth,
        height: bHeight
      } = bounds(nodeB);

      const overlapX = p.max(0, p.sub(p.min(aRight, bRight), p.max(aLeft, bLeft)));
      const overlapY = p.max(0, p.sub(p.min(aBottom, bBottom), p.max(aTop, bTop)));

      const normOverlapX = p.div(overlapX, p.max(1, p.min(aWidth, bWidth)));
      const normOverlapY = p.div(overlapY, p.max(1, p.min(aHeight, bHeight)));

      const overlapFraction = p.mul(100, p.mul(normOverlapX, normOverlapY));

      setConstraints({
        [nodeA.localUniqId(nodeB.localUniqId('disjoint'))]: p.absVal(overlapFraction)
      });
    },

    // Neighbours
    adjacentX: (nodeA: Node, nodeB: Node, padding = 0) => {
      const { right: aRight } = bounds(nodeA);
      const { left: bLeft } = bounds(nodeB);

      setConstraints({
        [nodeA.localUniqId(nodeB.localUniqId('adjacentX'))]: lessThanWithPadding(
          aRight,
          bLeft,
          padding
        )
      });
    },

    // Centering in container
    centerX: (containerNode: Node, node: Node) => {
      const { left: nLeft, right: nRight } = bounds(node);
      const { left: cLeft, right: cRight } = bounds(containerNode);

      const distToLeft = p.sub(nLeft, cLeft);
      const distToRight = p.sub(cRight, nRight);

      const imbalance = p.absVal(p.sub(distToLeft, distToRight));

      setConstraints({
        [node.localUniqId(containerNode.localUniqId('centerX'))]: p.log2(imbalance)
      });
    },

    centerY: (containerNode: Node, node: Node) => {
      const { top: nTop, bottom: nBottom } = bounds(node);
      const { top: cTop, bottom: cBottom } = bounds(containerNode);

      const distToTop = p.sub(nTop, cTop);
      const distToBottom = p.sub(cBottom, nBottom);

      const imbalance = p.absVal(p.sub(distToTop, distToBottom));

      setConstraints({
        [node.localUniqId(containerNode.localUniqId('centerY'))]: p.log2(imbalance)
      });
    }
  };

  const variable = (name: string): p.Var => {
    // Check if variable already exists
    if (name in variables) {
      return variables[name].variable;
    }

    // Create new variable in the current scope
    console.log(`Creating new variable ${name}`);

    const varRange: Interval = { min: 1, max: 1000 };
    const varInfo = { variable: p.variable(0), range: varRange };

    setConstraints({
      [`${name}-min`]: p.lessThan(varInfo.range.min, varInfo.variable),
      [`${name}-max`]: p.lessThan(varInfo.variable, varInfo.range.max)
    });

    // if (unitSize) {
    //   // Snap variable to nearest unit size using a soft constraint
    //   setConstraints({
    //     [`${name}-snap`]: snapModulo(varInfo.variable, unitSize, 0.1)
    //   });
    // }

    variables[name] = varInfo;
    return varInfo.variable;
  };

  const nodeContentTexts = $state({} as Record<string, ReactiveValue<string>>);
  const nodeContentClientWidths = $state({} as Record<string, ReactiveValue<number>>);
  const nodeContentClientHeights = $state({} as Record<string, ReactiveValue<number>>);

  const liveNodeContentText = (nodeId: string): { value: string } => {
    if (!nodeContentTexts[nodeId]) {
      nodeContentTexts[nodeId] = { value: '' };
    }
    return nodeContentTexts[nodeId];
  };

  const liveNodeContentClientWidth = (nodeId: string): { value: number } => {
    if (!nodeContentClientWidths[nodeId]) {
      nodeContentClientWidths[nodeId] = { value: 0 };
    }
    return nodeContentClientWidths[nodeId];
  };

  const liveNodeContentClientHeight = (nodeId: string): { value: number } => {
    if (!nodeContentClientHeights[nodeId]) {
      nodeContentClientHeights[nodeId] = { value: 0 };
    }
    return nodeContentClientHeights[nodeId];
  };

  const createNode = (config: NodeConfig = { style: {} }) => {
    const id = `node-${Object.keys(nodes).length + 1}`;

    if (config.style.x !== undefined) {
      config.style.left = config.style.x;
      delete config.style.x;
    }

    if (config.style.y !== undefined) {
      config.style.top = config.style.y;
      delete config.style.y;
    }

    config = {
      style: {
        width: `?<`,
        height: `?<`,
        left: `?`,
        top: `?`,
        ...config.style
      }
    };

    const localUniqId = (suffix: string) => `${id}-${suffix}`;

    const node: Node = {
      id,
      content: undefined,
      style: {},
      constraints: new SvelteMap<string, p.Num>(),
      localUniqId,
      setContent: (content: string) => {
        liveNodeContentText(node.id).value = content;

        node.content = {
          text: liveNodeContentText(node.id),
          clientWidth: liveNodeContentClientWidth(node.id),
          clientHeight: liveNodeContentClientHeight(node.id)
        };
        return node;
      }
    };

    for (const [key, value] of Object.entries(config.style)) {
      if (typeof value === 'string' && value[0] === '?') {
        // Implicit variable (default)
        const varName = parseVariableName(key);
        const varId = localUniqId(varName);
        const varInstance = variable(varId);
        node.style[key] = {
          type: 'variable',
          varId
        };
        if (value.length > 1 && value[1] === '<') {
          // Minimize variable ("?<")
          setConstraints({
            [node.localUniqId(`minimize-${key}`)]: p.log2(varInstance)
          });
        }
      } else if (typeof value === 'string' && value[0] === '$') {
        // Explicit variable (e.g. "$width" -> variable named "width")
        const varName = parseVariableName(value.slice(1));
        const varId = globals.byName(varName);
        variable(varId);
        node.style[key] = {
          type: 'variable',
          varId
        };
      } else if (typeof value === 'number') {
        // A number/string is treated as a constant CSS attribute
        node.style[key] = {
          type: 'constant',
          value: value
        };
      } else if (typeof value === 'string') {
        node.style[key] = {
          type: 'fixed',
          value
        };
      }
    }

    nodes[node.id] = node;

    // Min width/height constraints based on content size
    $effect(() => {
      if (!node.content) {
        return;
      }

      constraints.set(
        node.localUniqId('at-least-content-width'),
        p.lessThan(
          num(roundToUnit(node.content.clientWidth.value + unitSize / 2)),
          num(node.style.width)
        )
      );

      constraints.set(
        node.localUniqId('at-least-content-height'),
        p.lessThan(
          num(roundToUnit(node.content.clientHeight.value + unitSize / 2)),
          num(node.style.height)
        )
      );

      dirty = true;
    });

    return node;
  };

  const root = createNode({
    style: {
      width: rootWidth ?? '?',
      height: rootHeight ?? '?',
      left: 0,
      top: 0
    }
  });

  console.log('Created root node with id:', nodes);

  let dirty = $state(true);

  $effect(() => {
    if (!dirty) {
      return;
    }
    tick().then(() => {
      solve();
    });
  });

  const solve = async () => {
    console.log('====================== SOLVE ======================');
    console.log(`>>> Variables (n=${Object.keys(variables).length}):`, variables);
    console.log(`>>> Constraints (n=${Object.keys(allConstraints).length}):`, allConstraints);

    // Randomize initial variable values to help solver escape local minima
    for (const { variable, range } of Object.values(variables)) {
      const randomValue = Math.random() * (range.max - range.min) + range.min;
      variable.val = randomValue;
    }

    // const cons = $state.snapshot<Record<string, p.Num>>(constraints);

    const solveIteration = async () => {
      const problem = await p.problem({
        constraints: allConstraints
      });

      const result = problem.start({}).run({});
      console.log('Solver result:', result);

      // Update values
      for (const { variable } of Object.values(variables)) {
        const solvedValue = result.vals.get(variable) as number;
        variable.val = roundToUnit(solvedValue);
      }
    };

    await solveIteration();

    output.views = Object.values(nodes).map((node) => {
      const style: Record<string, string> = {};
      for (const [key, value] of Object.entries(node.style)) {
        if (value.type === 'variable') {
          const varValue = variables[value.varId].variable.val;
          const [cssKey, cssValue] = toCSSrule(key, varValue);
          if (node.id === 'node-2' || node.id === 'node-3') {
            console.log(`Setting style ${cssKey} to ${cssValue} for node ${node.id}`);
          }
          style[cssKey] = cssValue;
        } else if (value.type === 'constant') {
          const [cssKey, cssValue] = toCSSrule(key, roundToUnit(value.value));
          style[cssKey] = cssValue;
        } else if (value.type === 'fixed') {
          const [cssKey, cssValue] = toCSSrule(key, value.value);
          style[cssKey] = cssValue;
        }
      }
      return {
        nodeId: node.id,
        style,
        content: node.content
      } as NodeView;
    });

    dirty = false;
  };

  return {
    get ready(): boolean {
      return !dirty;
    },

    get views(): NodeView[] {
      return output.views;
    },

    get constraint() {
      return constraint;
    },

    get createNode() {
      return (style?: Record<string, '?' | string | number>) => {
        return createNode({ style: style ?? {} });
      };
    },

    get root() {
      return root;
    },

    addVariable: variable,
    solve
  };
}
