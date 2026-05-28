import * as p from '@penrose/core';
import { tick } from 'svelte';
import * as _ from 'lodash-es';
import { LazyTemporalMap } from './temporal';

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

interface Variable extends p.Var {
  id: string;
  uuid: string;
  randomInit: Interval;
}

type Temporal<T> = {
  at: Record<number, T>;
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

  const nodes = {} as Record<string, Node>;

  const constraintsAtTime = [{}] as Record<string, p.Num>[];
  const constraints = () => constraintsAtTime[time];

  const setConstraints = (newConstraints: Record<string, p.Num>) => {
    for (const [key, value] of Object.entries(newConstraints)) {
      constraints()[key] = value;
    }
  };

  const defineConstraint = <Args extends unknown[]>(
    consName: string,
    constraintFn: (...args: Args) => Array<p.Num>
  ) => {
    return (...args: Args) => {
      const nodes = args.filter((arg): arg is Node => typeof arg === 'object' && 'id' in arg!);
      const vars = args.filter((arg): arg is Variable => typeof arg === 'object' && 'val' in arg!);
      const nodeIdsConcat = nodes.map((n) => n.localUniqId('')).join('');
      const varIdsConcat = vars.map((v) => v.uuid).join('-');
      const constraintExprs = constraintFn(...args);
      const constraintKeys = constraintExprs.map((_, i) => {
        return `${consName}-${nodeIdsConcat}${varIdsConcat}${i}`;
      });
      const newConstraints: Record<string, p.Num> = {};
      constraintKeys.forEach((key, i) => {
        newConstraints[key] = constraintExprs[i];
      });
      setConstraints(newConstraints);
    };
  };

  const createVariable = (key: string): Variable => {
    return {
      ...p.variable(0),
      id: key,
      uuid: crypto.randomUUID().slice(0, 8),
      randomInit: { min: 1, max: 1000 }
    };
  };

  const variables = new LazyTemporalMap<string, Variable>(createVariable);

  let time = 0;
  const addTimeStep = () => {
    constraintsAtTime.push({});
    console.log(`Adding time step ${time + 1}`);

    time += 1;
  };

  const globals = {
    byName: (name: string) => {
      console.log(`Looking up global variable by name: ${name}`);
      return `global-${name}`;
    }
  };

  const output = $state({
    views: { at: { 0: [] } } as Temporal<NodeView[]>
  });

  const num = (value: StyleValue | ReactiveValue<number> | number, t = time): p.Num => {
    if (typeof value === 'number') {
      return value;
    }

    if (typeof value === 'object' && 'value' in value) {
      return (value as ReactiveValue<number>).value;
    }

    const styleValue = value as StyleValue;

    if (styleValue.type === 'variable') {
      return variables.lookup(styleValue.varId).at(t);
    }

    if (styleValue.type === 'constant') {
      return styleValue.value as number;
    }
    throw new Error(`Cannot convert ${styleValue.type} to number`);
  };

  const bounds = (node: Node, t: number = time) => {
    const left = num(node.style.left, t);
    const top = num(node.style.top, t);
    const width = num(node.style.width, t);
    const height = num(node.style.height, t);
    const right = p.add(left, width);
    const bottom = p.add(top, height);

    return { left, top, right, bottom, width, height };
  };

  const constraint = {
    eq: defineConstraint('eq', (a: p.Num, b: p.Num) => {
      return [p.log2(p.absVal(p.sub(a, b)))];
    }),

    between: defineConstraint('between', (value: p.Num, range: Interval) => {
      const { min, max } = range;
      return [p.lessThan(min, value), p.lessThan(value, max)];
    }),

    assign: defineConstraint('assign', (nodeA: Node, nodeB: Node) => {
      const { left: aLeft, top: aTop, right: aRight, bottom: aBottom } = bounds(nodeA);
      const { left: bLeft, top: bTop, right: bRight, bottom: bBottom } = bounds(nodeB);
      return [
        p.mul(p.absVal(p.sub(aLeft, bLeft)), 1),
        p.mul(p.absVal(p.sub(aTop, bTop)), 1),
        p.mul(p.absVal(p.sub(aRight, bRight)), 1),
        p.mul(p.absVal(p.sub(aBottom, bBottom)), 1)
      ];
    }),

    contains: defineConstraint('contains', (containerNode: Node, node: Node) => {
      const { left: cLeft, top: cTop, right: cRight, bottom: cBottom } = bounds(containerNode);
      const { left, top, right, bottom } = bounds(node);

      return [
        lessThanWithPadding(cLeft, left, 0),
        lessThanWithPadding(right, cRight, 0),
        lessThanWithPadding(cTop, top, 0),
        lessThanWithPadding(bottom, cBottom, 0)
      ];
    }),

    disjoint: defineConstraint('disjoint', (nodeA: Node, nodeB: Node) => {
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

      return [overlapFraction];
    }),

    adjacentX: defineConstraint('adjacentX', (nodeA: Node, nodeB: Node, padding: number = 0) => {
      const { right: aRight } = bounds(nodeA);
      const { left: bLeft } = bounds(nodeB);

      return [lessThanWithPadding(aRight, bLeft, padding)];
    }),

    centerX: defineConstraint('centerX', (containerNode: Node, node: Node) => {
      const { left: nLeft, right: nRight } = bounds(node);
      const { left: cLeft, right: cRight } = bounds(containerNode);

      const distToLeft = p.sub(nLeft, cLeft);
      const distToRight = p.sub(cRight, nRight);
      const imbalance = p.absVal(p.sub(distToLeft, distToRight));

      return [p.log2(imbalance)];
    })
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
        const varInstance = variables.lookup(varId).at(time);
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
        node.style[key] = {
          type: 'variable',
          varId
        };
        console.log(`Created variable ${varId} for node ${node.id} style ${key}`);
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

      // across all constaint times
      for (let t = 0; t <= 0; t++) {
        const consAtTime = constraintsAtTime[t];

        const { width, height } = bounds(node, t);

        consAtTime[node.localUniqId('at-least-content-width')] = p.mul(
          10,
          lessThanWithPadding(
            num(roundToUnit(node.content.clientWidth.value + unitSize / 2)),
            width,
            0
          )
        );

        consAtTime[node.localUniqId('at-least-content-height')] = p.mul(
          10,
          lessThanWithPadding(
            num(roundToUnit(node.content.clientHeight.value + unitSize / 2)),
            height,
            0
          )
        );
      }

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
    // console.log(variables);
    const seqVariables = variables.toSequence(time);
    console.log(seqVariables);

    const seqConstraints = constraintsAtTime.reduce(
      (cons, consAtTime, t) => {
        const newConsAtTime = _.cloneDeepWith(consAtTime, (value) => {
          if (
            typeof value === 'object' &&
            value !== null &&
            'tag' in value &&
            value.tag === 'Var'
          ) {
            console.log('Cloning constraint value:', value);
            console.log(
              'Replacing with variable value from seqVariables:',
              seqVariables[value.id][t]
            );
            return seqVariables[value.id][t];
          }
          return undefined;
        }) as Record<string, p.Num>;

        const prefix = `t${t}-`;
        for (const [key, value] of Object.entries(newConsAtTime)) {
          cons[`${prefix}${key}`] = value;
        }
        return cons;
      },
      {} as Record<string, p.Num>
    );
    // constraintsAtTime.forEach((consAtTime, cTime) => {
    //   const prefix = `t${cTime}-`;
    //   for (const [key, value] of Object.entries(consAtTime)) {
    //     seqConstraints[`${prefix}${key}`] = value;
    //   }
    // });

    console.log('====================== SOLVE ======================');
    console.log(`>>> Variables (n=${Object.keys(seqVariables).length}):`, seqVariables);
    console.log(`>>> Constraints (n=${Object.keys(seqConstraints).length}):`, seqConstraints);

    // Randomize initial variable values to help solver escape local minima
    for (const variable of Object.values(seqVariables)) {
      // Always at least one time step if variable exists
      const firstTimeStep = variable[0];
      const initValue =
        Math.random() * (firstTimeStep.randomInit.max - firstTimeStep.randomInit.min) +
        firstTimeStep.randomInit.min;

      for (const timeKey in variable) {
        variable[timeKey].val = initValue;
      }
    }

    const solveIteration = async () => {
      const problem = await p.problem({
        constraints: Object.values(seqConstraints)
      });

      const result = problem.start({}).run({});
      console.log('Solver result:', result);

      // Update values
      for (const variable of Object.values(seqVariables)) {
        for (const timeKey in variable) {
          const solvedValue = result.vals.get(variable[timeKey]) as number;
          variable[timeKey].val = roundToUnit(solvedValue);
        }
      }
    };

    await solveIteration();

    output.views = {
      at: _.fromPairs(
        _.range(time + 1).map((t) => {
          const nodeViews = Object.values(nodes).map((node) => {
            const style: Record<string, string> = {};
            for (const [key, value] of Object.entries(node.style)) {
              if (value.type === 'variable') {
                const varValue = seqVariables[value.varId][t].val;
                const [cssKey, cssValue] = toCSSrule(key, varValue);
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

          return [t, nodeViews];
        })
      )
    };

    dirty = false;
  };

  return {
    get ready(): boolean {
      return !dirty;
    },

    get views(): Temporal<NodeView[]> {
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

    get step() {
      return function (f: () => void) {
        addTimeStep();
        f();
      };
    },

    get timeSteps() {
      return time;
    },

    solve
  };
}
