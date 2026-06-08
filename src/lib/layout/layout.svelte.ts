import * as penrose from '@penrose/core';
import * as _ from 'lodash-es';
import {
  Node,
  type NodeView,
  type StyleValue,
  type NodeHandle,
  type NodeStyle,
  type WithDefaultStyle,
  getNodeHandleId
} from './node.svelte';
import { toCSSrule, toCSS } from './style';
import { randomUUID } from './utils';
import { tick } from 'svelte';
import { SvelteMap } from 'svelte/reactivity';
import { debugPrettyPrint } from './debug';

export type StepNodeSpec<StyleT extends NodeStyle = NodeStyle> = readonly [
  style: StyleT,
  content?: string
];

type StepHandles<Specs extends readonly StepNodeSpec[]> = {
  [K in keyof Specs]: Specs[K] extends readonly [infer StyleT, string?]
    ? StyleT extends NodeStyle
      ? NodeHandle<WithDefaultStyle<StyleT>>
      : never
    : never;
};

export type Interval = {
  min: number;
  max: number;
};

export class Variable implements penrose.Var {
  tag: 'Var';
  val: number;
  scope: LayoutCSPScope;
  id: string;
  uuid: string;
  randomInit: Interval;

  constructor(id: string, scope: LayoutCSPScope) {
    this.tag = 'Var';
    this.val = 0;
    this.id = id;
    this.scope = scope;
    this.uuid = randomUUID();
    this.randomInit = { min: 1, max: 1000 };
  }

  public constraint<Rest extends penrose.Num[]>(
    c: (self: Variable, ...args: Rest) => penrose.Num,
    ...args: Rest
  ): this {
    const constraint = this.scope.constraint(randomUUID());

    constraint.set(c(this, ...args));

    return this;
  }
}

export class Constraint {
  #id: string;
  #expr: penrose.Num;
  #scope: LayoutCSPScope;

  constructor(id: string, scope: LayoutCSPScope) {
    this.#id = id;
    this.#expr = 0;
    this.#scope = scope;
  }

  public get id() {
    return this.#id;
  }

  public get expr() {
    return this.#expr;
  }

  public get scope() {
    return this.#scope;
  }

  public set(expr: penrose.Num) {
    this.#expr = expr;
  }
}

export class LayoutCSPScope {
  private namespace: string;
  private layout: LayoutCSP;

  constructor(layout: LayoutCSP, namespace: string) {
    this.namespace = namespace;
    this.layout = layout;
  }

  public variable(id: string): Variable {
    id = this.idWithNamespace(id, this.namespace);
    return this.layout._defaultVariable(id, () => new Variable(id, this));
  }

  public constraint(id: string): Constraint {
    id = this.idWithNamespace(id, this.namespace);
    return this.layout._defaultConstraint(id, () => new Constraint(id, this));
  }

  private idWithNamespace(key: string, namespace: string): string {
    return `${namespace}-${key}`;
  }
}

export class LayoutCSP {
  #time: number = $state(-1);
  #unitSize: number;

  #root: Node | undefined;
  #globalScope: LayoutCSPScope;

  #nodes: SvelteMap<string, Node>[] = [new SvelteMap()];
  #nodeIdCounter: number = 0;

  #variables: SvelteMap<string, Variable>;
  #constraints: SvelteMap<string, Constraint>;

  #views: NodeView[][] = $state([]);

  private constructor(unitSize: number = 1) {
    this.#unitSize = unitSize;
    this.#variables = new SvelteMap<string, Variable>();
    this.#constraints = new SvelteMap<string, Constraint>();
    this.#globalScope = new LayoutCSPScope(this, 'global');
  }

  public static async create(
    canvasWidth: number,
    canvasHeight: number,
    unitSize: number = 1
  ): Promise<LayoutCSP> {
    const layout = new LayoutCSP(unitSize);
    const root = await Node.create(layout, 'root', {
      style: {
        width: canvasWidth,
        height: canvasHeight,
        left: 0,
        top: 0
      }
    });
    layout.#root = root;
    await tick();
    return layout;
  }

  private ensureRoot() {
    if (this.#root === undefined) {
      throw new Error('Root node is not defined.');
    }
  }

  private async node<StyleT extends NodeStyle>(
    style: StyleT,
    content?: string
  ): Promise<NodeHandle<WithDefaultStyle<StyleT>>> {
    this.ensureRoot();

    const nodeId = `node-${this.#nodeIdCounter++}`;

    const node = await Node.create(this, nodeId, { style }, content);

    this.#nodes[this.time].set(node.id, node);
    node.within(this.#root!);

    return node.handle;
  }

  public async step<const Specs extends readonly StepNodeSpec[]>(
    removeNodes: readonly (string | NodeHandle<NodeStyle>)[] = [],
    nodes: Specs = [] as unknown as Specs
  ): Promise<StepHandles<Specs>> {
    this.#time += 1;

    const removeNodeIds = removeNodes.map((node) =>
      typeof node === 'string' ? node : getNodeHandleId(node)
    );

    this.#nodes[this.time] =
      this.time > 0
        ? new SvelteMap(
            this.#nodes[this.time - 1]
              .entries()
              .filter(([nodeId]) => !removeNodeIds.includes(nodeId))
          )
        : new SvelteMap();

    const handles = await Promise.all(
      nodes.map(async ([style, content]) => {
        return await this.node(style, content);
      })
    );

    return handles as StepHandles<Specs>;
  }

  public get time() {
    return this.#time;
  }

  public get unitSize() {
    return this.#unitSize;
  }

  public _defaultVariable(id: string, factory: () => Variable): Variable {
    if (!this.#variables.has(id)) {
      this.#variables.set(id, factory());
    }
    return this.#variables.get(id)!;
  }

  public _defaultConstraint(id: string, factory: () => Constraint): Constraint {
    if (!this.#constraints.has(id)) {
      this.#constraints.set(id, factory());
    }
    return this.#constraints.get(id)!;
  }

  public variable(id: string): Variable {
    return this.#globalScope.variable(id);
  }

  public constraint(id: string): Constraint {
    return this.#globalScope.constraint(id);
  }

  public async solve() {
    this.ensureRoot();

    const nodes = this.#nodes.map((nodeMap) => ({
      root: this.#root!.asObject(),
      ...Object.fromEntries(nodeMap.entries().map(([id, node]) => [id, node.asObject()]))
    }));
    console.log(nodes);
    const variables = Object.fromEntries(this.#variables.entries());
    const constraints = Object.fromEntries(
      this.#constraints.entries().map(([id, constraint]) => [id, constraint.expr])
    );

    // Randomize initial variable values to help solver escape local minima
    for (const v of _.values(variables)) {
      v.val = Math.random() * (v.randomInit.max - v.randomInit.min) + v.randomInit.min;
    }

    console.log('====================== SOLVE ======================');
    console.log(`>>> Variables (n=${Object.keys(variables).length}):`);
    console.log(debugPrettyPrint(variables, 22));
    console.log(`=== CONSTRAINTS (n=${Object.keys(constraints).length}) ===`);
    console.log(debugPrettyPrint(constraints, 22));

    const solveIteration = async () => {
      const problem = await penrose.problem({
        constraints: _.values(constraints)
      });

      const result = problem.start({}).run({});
      console.log('>>> Solver result:', result);

      // Update values
      for (const variable of Object.keys(variables)) {
        const solvedValue = result.vals.get(variables[variable]);
        if (solvedValue === undefined) {
          console.warn(`No solved value for variable ${variable}`);
          continue;
        }
        variables[variable].val = solvedValue;
      }
    };

    await solveIteration();

    console.log(
      `>>> Variables [SOLVED] (n=${Object.keys(variables).length}):`,
      debugPrettyPrint(variables, 22)
    );

    this.#views = _.range(this.time + 1).map((t) => {
      const nodeViews = _.entries(nodes[t]).map(([nodeId, node]) => {
        const style = Object.fromEntries(
          _.entries(node.style).map(([key, value]) => {
            if (value.type === 'variable') {
              const varValue = variables[value.varId].val;
              return toCSSrule(key, varValue);
            } else {
              return toCSSrule(key, value.value);
            }
          })
        );
        return {
          nodeId,
          style,
          css: toCSS(style),
          content: node.content
        } as NodeView;
      });

      return nodeViews;
    });
  }

  public get views() {
    return this.#views;
  }

  public num = (value: StyleValue | number): penrose.Num => {
    if (typeof value === 'number') {
      return value;
    }

    const styleValue = value as StyleValue;

    if (styleValue.type === 'variable') {
      if (!this.#variables.has(styleValue.varId)) {
        throw new Error(`Variable with id ${styleValue.varId} does not exist`);
      }
      return this.#variables.get(styleValue.varId)!;
    }

    if (styleValue.type === 'constant') {
      return styleValue.value as number;
    }
    throw new Error(`Cannot convert ${styleValue.type} to number`);
  };
}
