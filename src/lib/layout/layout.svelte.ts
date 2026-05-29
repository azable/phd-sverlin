import * as penrose from '@penrose/core';
import * as _ from 'lodash-es';
import { LazyTemporal, LazyUniform, LazyTemporalMap, type Temporal } from './temporal';
import { type StyleValue, Node, type NodeView } from './node.svelte';
import { toCSSrule } from './style';
import { randomUUID } from './utils';
import { tick } from 'svelte';

export const p = {
  ...penrose,
  lessThanWithPadding: (a: penrose.Num, b: penrose.Num, padding: penrose.Num): penrose.Num => {
    const gap = penrose.add(penrose.sub(a, b), padding);
    const violation = penrose.max(gap, 0);
    const penalty = penrose.pow(violation, 2);
    return penalty;
  }
};

export type Interval = {
  min: number;
  max: number;
};

export interface Variable extends penrose.Var {
  id: string;
  uuid: string;
  randomInit: Interval;
}

export class LayoutCSP {
  #time: number = $state(0);
  #unitSize: number;
  #dirty: boolean = $state(false);

  #nodes: Record<string, Node> = {};

  #uniforms: LazyTemporalMap<string, Variable>;
  #varyings: LazyTemporalMap<string, Variable>;
  #constraints: LazyTemporalMap<string, penrose.Num>;

  #views: NodeView[][] = $state([]);

  constructor(unitSize: number = 1) {
    this.#unitSize = unitSize;

    const makeVariable = (key: string): Variable => {
      return {
        ...penrose.variable(0),
        id: key,
        uuid: randomUUID(),
        randomInit: { min: 1, max: 1000 }
      };
    };

    this.#uniforms = new LazyTemporalMap<string, Variable>(LazyUniform, makeVariable);
    this.#varyings = new LazyTemporalMap<string, Variable>(LazyTemporal, makeVariable);

    this.#constraints = new LazyTemporalMap<string, penrose.Num>(LazyTemporal, () =>
      penrose.variable(0)
    );

    $effect(() => {
      // Ensure always up to date by next tick if scheduled to resolve
      if (!this.#dirty) {
        return;
      }
      console.log('>>> Scheduled re-solve at next tick');
      tick().then(() => {
        this.solve();
      });
    });
  }

  public registerNode(id: string, node: Node) {
    if (id in this.#nodes) {
      throw new Error(`Node with id ${id} already exists`);
    }
    this.#nodes[id] = node;
  }

  public getNodes() {
    return this.#nodes;
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

  public constraint(namespace: string, id?: string): Temporal<penrose.Num> {
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
      const nodeViews = Object.values(this.#nodes).map((node) => {
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

  public num = (value: StyleValue | number, t = this.#time): penrose.Num => {
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
    constraintFn: (...args: Args) => Array<penrose.Num>
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

  public constraint(id: string): Temporal<penrose.Num> {
    return this.layout.constraint(this.namespace, id);
  }
}
