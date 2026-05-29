import * as p from '@penrose/core';
import { tick } from 'svelte';
import * as _ from 'lodash-es';
import { LazyTemporal, LazyUniform, LazyTemporalMap, type Temporal } from './temporal';

const randomUUID = (): string => {
  return crypto.randomUUID().slice(0, 8);
};

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

export type NodeConfig = {
  style: Record<string, string | number | Temporal<Variable>>;
};

export class LayoutCSP {
  #time: number = $state(0);
  #unitSize: number;
  #dirty: boolean = $state(true);

  #uniforms: LazyTemporalMap<string, Variable>;
  #varyings: LazyTemporalMap<string, Variable>;
  #constraints: LazyTemporalMap<string, p.Num>;

  #views: NodeView[][] = $state([]);

  constructor(unitSize: number = 1) {
    this.#unitSize = unitSize;

    const makeVariable = (key: string): Variable => {
      return {
        ...p.variable(0),
        id: key,
        uuid: randomUUID(),
        randomInit: { min: 1, max: 1000 }
      };
    };

    this.#uniforms = new LazyTemporalMap<string, Variable>(LazyUniform, makeVariable);
    this.#varyings = new LazyTemporalMap<string, Variable>(LazyTemporal, makeVariable);

    this.#constraints = new LazyTemporalMap<string, p.Num>(LazyTemporal, () => p.variable(0));

    $effect(() => {
      // Ensure always up to date by next tick if scheduled to resolve
      if (!this.#dirty) {
        return;
      }
      tick().then(() => {
        this.solve();
      });
    });
  }

  public step() {
    this.#time += 1;
  }

  public get time() {
    return this.#time;
  }

  public get unitSize() {
    return this.#unitSize;
  }

  public get isDirty() {
    return this.#dirty;
  }

  public scheduleResolve() {
    this.#dirty = true;
  }

  private ensureUniqId(id: string | undefined): string {
    if (id === undefined || id === null) {
      return randomUUID();
    }
    return id;
  }

  public uniform(namespace: string, id?: string): Temporal<Variable> {
    id = this.ensureUniqId(id);
    return this.#uniforms.lookup(this.idWithNamespace(`uniform-${id}`, namespace));
  }

  public varying(namespace: string, id?: string): Temporal<Variable> {
    id = this.ensureUniqId(id);
    return this.#varyings.lookup(this.idWithNamespace(`varying-${id}`, namespace));
  }

  public variable(id: string): Temporal<Variable> {
    if (id.includes('uniform')) {
      return this.#uniforms.lookup(id);
    } else if (id.includes('varying')) {
      return this.#varyings.lookup(id);
    }
    throw new Error(`Variable id must contain either 'uniform' or 'varying': ${id}`);
  }

  public constraint(namespace: string, id?: string): Temporal<p.Num> {
    id = this.ensureUniqId(id);
    return this.#constraints.lookup(this.idWithNamespace(id, namespace));
  }

  public async solve() {
    const matVariables = {
      ...this.#uniforms.materialize(this.time),
      ...this.#varyings.materialize(this.time)
    };
    const matConstraints = this.#constraints.materialize(this.time);

    // Randomize initial variable values to help solver escape local minima
    for (const variable of Object.keys(matVariables)) {
      // Always at least one time step if variable exists
      const firstTimeStep = matVariables[variable][0];
      const initValue =
        Math.random() * (firstTimeStep.randomInit.max - firstTimeStep.randomInit.min) +
        firstTimeStep.randomInit.min;

      for (const timeKey in matVariables[variable]) {
        matVariables[variable][timeKey].val = initValue;
      }
    }

    console.log('====================== SOLVE ======================');
    console.log(
      `>>> Variables (n=${Object.keys(matVariables).length}):`,
      window.structuredClone(matVariables)
    );
    console.log(
      `>>> Constraints (n=${Object.keys(matConstraints).length}):`,
      window.structuredClone(matConstraints)
    );

    const solveIteration = async () => {
      const problem = await p.problem({
        constraints: _.flatten(Object.values(matConstraints))
      });

      const result = problem.start({}).run({});

      // Update values
      for (const variable of Object.keys(matVariables)) {
        for (const timeKey in matVariables[variable]) {
          const solvedValue = result.vals.get(matVariables[variable][timeKey]);
          if (solvedValue === undefined) {
            console.warn(`No solved value for variable ${variable} at time ${timeKey}`);
            continue;
          }
          matVariables[variable][timeKey].val = solvedValue;
        }
      }
    };

    await solveIteration();

    console.log(
      `>>> Variables [SOLVED] (n=${Object.keys(matVariables).length}):`,
      window.structuredClone(matVariables)
    );

    this.#views = _.range(this.time + 1).map((t) => {
      const nodeViews = Object.values(Node.all).map((node) => {
        const style: Record<string, string> = {};
        for (const [key, value] of Object.entries(node.style)) {
          if (value.type === 'variable') {
            const varValue = matVariables[value.varId][t].val;
            const [cssKey, cssValue] = toCSSrule(key, varValue);
            style[cssKey] = cssValue;
          } else if (value.type === 'constant') {
            const [cssKey, cssValue] = toCSSrule(key, value.value);
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

      return nodeViews;
    });

    this.#dirty = false;
  }

  public get views() {
    return this.#views;
  }

  public num = (value: StyleValue | number, t = this.#time): p.Num => {
    if (typeof value === 'number') {
      return value;
    }

    const styleValue = value as StyleValue;

    if (styleValue.type === 'variable') {
      return this.variable(styleValue.varId).at(t);
    }

    if (styleValue.type === 'constant') {
      return styleValue.value as number;
    }
    throw new Error(`Cannot convert ${styleValue.type} to number`);
  };

  public defineConstraint = <Args extends unknown[]>(
    consName: string,
    constraintFn: (...args: Args) => Array<p.Num>
  ) => {
    return (...args: Args) => {
      const nodes = args.filter((arg): arg is Node => typeof arg === 'object' && 'id' in arg!);
      const vars = args.filter(
        (arg): arg is Temporal<Variable> => typeof arg === 'object' && 'at' in arg!
      );
      const varsAtTime = vars.map((v) => v.at(this.time));
      const nodeIdsConcat = nodes.map((n) => n.id).join('');
      const varIdsConcat = varsAtTime.map((v) => v.uuid).join('-');
      const constraintExprs = constraintFn(...args);
      const constraintKeys = constraintExprs.map((_, i) => {
        return `${consName}-${nodeIdsConcat}${varIdsConcat}${i}`;
      });
      constraintKeys.forEach((key, i) => {
        this.#constraints.lookup(key).setAt(this.time, constraintExprs[i]);
      });
    };
  };

  private idWithNamespace(key: string, namespace: string): string {
    return `${namespace}-${key}`;
  }
}

export class LayoutCSPScope {
  private namespace: string;
  private layout: LayoutCSP;

  constructor(layout: LayoutCSP, namespace: string) {
    this.namespace = namespace;
    this.layout = layout;
  }

  public uniform(id: string): Temporal<Variable> {
    return this.layout.uniform(this.namespace, id);
  }

  public varying(id: string): Temporal<Variable> {
    return this.layout.varying(this.namespace, id);
  }

  public constraint(id: string): Temporal<p.Num> {
    return this.layout.constraint(this.namespace, id);
  }
}

export class Node {
  public static all = {} as Record<string, Node>;

  #layout: LayoutCSP;
  #scope: LayoutCSPScope;

  #id: string;
  #style: Record<string, StyleValue>;
  #content: NodeContent = $state({
    text: '',
    clientWidth: 0,
    clientHeight: 0
  });

  constructor(layout: LayoutCSP, config: NodeConfig) {
    this.#layout = layout;
    this.#id = `node-${Object.keys(Node.all).length + 1}`;
    this.#scope = new LayoutCSPScope(layout, this.#id);

    config = {
      style: {
        width: config.style.width ?? this.#scope.varying('width'),
        height: config.style.height ?? this.#scope.varying('height'),
        left: config.style.left ?? this.#scope.varying('left'),
        top: config.style.top ?? this.#scope.varying('top'),
        ...config.style
      }
    };

    this.#style = _.mapValues(config.style, (value, key) => {
      if (typeof value === 'object' && 'at' in value && 'setAt' in value) {
        return {
          type: 'variable',
          varId: value.at(0).id
        } as StyleValue;
      } else if (typeof value === 'number') {
        return {
          type: 'constant',
          value
        } as StyleValue;
      } else if (typeof value === 'string') {
        return {
          type: 'fixed',
          value
        } as StyleValue;
      }
      throw new Error(`Invalid style value for key ${key}`);
    });

    Node.all[this.#id] = this;

    // Min width/height constraints based on content size
    $effect(() => {
      if (!this.#content) {
        return;
      }

      const { width, height } = this.bounds(0);

      this.#scope
        .constraint('at-least-content-width')
        .setAt(
          0,
          lessThanWithPadding(
            p.add(this.#layout.num(this.#content.clientWidth), this.#layout.unitSize),
            width,
            0
          )
        );

      this.#scope
        .constraint('at-least-content-height')
        .setAt(
          0,
          lessThanWithPadding(
            p.add(this.#layout.num(this.#content.clientHeight), this.#layout.unitSize),
            height,
            0
          )
        );

      this.#layout.scheduleResolve();
    });

    return this;
  }

  public get id() {
    return this.#id;
  }

  public get content() {
    return this.#content;
  }

  public get style(): Record<string, StyleValue> {
    return this.#style;
  }

  public bounds(time: number = this.#layout.time): Record<string, p.Num> {
    const left = this.#layout.num(this.style.left, time);
    const top = this.#layout.num(this.style.top, time);
    const width = this.#layout.num(this.style.width, time);
    const height = this.#layout.num(this.style.height, time);
    const right = p.add(left, width);
    const bottom = p.add(top, height);

    return {
      left,
      top,
      right,
      bottom,
      width,
      height
    };
  }

  public setContent(content: string) {
    this.#content.text = content;
    return this;
  }
}

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

export type NodeView = {
  nodeId: string;
  style: Record<string, string>;
  content?: NodeContent;
};

type NodeContent = {
  text: string;
  clientWidth: number;
  clientHeight: number;
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

  const layout = new LayoutCSP(unitSize);

  const root = new Node(layout, {
    style: {
      width: rootWidth ?? 1200,
      height: rootHeight ?? 800,
      left: 0,
      top: 0
    }
  });

  const constraint = {
    eq: layout.defineConstraint('eq', (a: Temporal<Variable>, b: Temporal<Variable>) => {
      return [p.log2(p.absVal(p.sub(a.at(layout.time), b.at(layout.time))))];
    }),

    between: layout.defineConstraint('between', (value: Temporal<Variable>, range: Interval) => {
      const { min, max } = range;
      return [p.lessThan(min, value.at(layout.time)), p.lessThan(value.at(layout.time), max)];
    }),

    assign: layout.defineConstraint('assign', (nodeA: Node, nodeB: Node) => {
      const { left: aLeft, top: aTop, right: aRight, bottom: aBottom } = nodeA.bounds(layout.time);
      const { left: bLeft, top: bTop, right: bRight, bottom: bBottom } = nodeB.bounds(layout.time);
      return [
        p.mul(p.absVal(p.sub(aLeft, bLeft)), 1),
        p.mul(p.absVal(p.sub(aTop, bTop)), 1),
        p.mul(p.absVal(p.sub(aRight, bRight)), 1),
        p.mul(p.absVal(p.sub(aBottom, bBottom)), 1)
      ];
    }),

    minimize: layout.defineConstraint('minimize', (value: Temporal<Variable>) => {
      return [p.log2(p.absVal(value.at(layout.time)))];
    }),

    contains: layout.defineConstraint('contains', (containerNode: Node, node: Node) => {
      const {
        left: cLeft,
        top: cTop,
        right: cRight,
        bottom: cBottom
      } = containerNode.bounds(layout.time);
      const { left, top, right, bottom } = node.bounds(layout.time);

      return [
        lessThanWithPadding(cLeft, left, 0),
        lessThanWithPadding(right, cRight, 0),
        lessThanWithPadding(cTop, top, 0),
        lessThanWithPadding(bottom, cBottom, 0)
      ];
    }),

    disjoint: layout.defineConstraint('disjoint', (nodeA: Node, nodeB: Node) => {
      const {
        left: aLeft,
        top: aTop,
        right: aRight,
        bottom: aBottom,
        width: aWidth,
        height: aHeight
      } = nodeA.bounds(layout.time);
      const {
        left: bLeft,
        top: bTop,
        right: bRight,
        bottom: bBottom,
        width: bWidth,
        height: bHeight
      } = nodeB.bounds(layout.time);

      const overlapX = p.max(0, p.sub(p.min(aRight, bRight), p.max(aLeft, bLeft)));
      const overlapY = p.max(0, p.sub(p.min(aBottom, bBottom), p.max(aTop, bTop)));

      const normOverlapX = p.div(overlapX, p.max(1, p.min(aWidth, bWidth)));
      const normOverlapY = p.div(overlapY, p.max(1, p.min(aHeight, bHeight)));

      const overlapFraction = p.mul(100, p.mul(normOverlapX, normOverlapY));

      return [overlapFraction];
    }),

    adjacentX: layout.defineConstraint(
      'adjacentX',
      (nodeA: Node, nodeB: Node, padding: number = 0) => {
        const { right: aRight } = nodeA.bounds(layout.time);
        const { left: bLeft } = nodeB.bounds(layout.time);

        return [lessThanWithPadding(aRight, bLeft, padding)];
      }
    ),

    centerX: layout.defineConstraint('centerX', (containerNode: Node, node: Node) => {
      const { left: nLeft, right: nRight } = node.bounds(layout.time);
      const { left: cLeft, right: cRight } = containerNode.bounds(layout.time);

      const distToLeft = p.sub(nLeft, cLeft);
      const distToRight = p.sub(cRight, nRight);
      const imbalance = p.absVal(p.sub(distToLeft, distToRight));

      return [p.log2(imbalance)];
    })
  };

  return {
    get ready(): boolean {
      return !layout.isDirty;
    },

    get views(): NodeView[][] {
      return layout.views;
    },

    get constraint() {
      return constraint;
    },

    get createNode() {
      return (style?: NodeConfig['style']) => {
        return new Node(layout, { style: style ?? {} });
      };
    },

    get root() {
      return root;
    },

    get timeSteps() {
      return layout.time;
    },

    step: layout.step.bind(layout),
    varying: layout.varying.bind(layout),
    uniform: layout.uniform.bind(layout),
    solve: layout.solve.bind(layout)
  };
}
