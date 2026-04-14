<script lang="ts">
  import { flip } from 'svelte/animate';

  // type Node<T> = {
  //   id: number;
  //   data: T;
  //   type: string;
  // };

  interface IntNode {
    id: number;
    annotations: string[];
    data: number;
    type: 'int';
  }

  interface ArrayNode<N extends AnyNode> {
    id: number;
    annotations: string[];
    data: N[];
    type: 'array';
  }

  type AnyNode = IntNode | ArrayNode<AnyNode>;

  const flatApplyNodes = <N extends AnyNode>(
    nodes: N[],
    fn: (node: AnyNode) => void = () => {}
  ): AnyNode[] => {
    let result: AnyNode[] = [];
    for (const node of nodes) {
      fn(node);
      result.push(node);
      if (node.type === 'array') {
        result = result.concat(flatApplyNodes(node.data, fn));
      }
    }
    return result;
  };

  let nextId = 0;

  const node = {
    int: (data: number): IntNode => {
      return {
        id: nextId++,
        data,
        type: 'int',
        annotations: []
      };
    },

    array: <N extends AnyNode>(data: N[]): ArrayNode<N> => {
      return {
        id: nextId++,
        data,
        type: 'array',
        annotations: []
      };
    }
  };

  const dt = {
    int: (initValue: number) => node.int(initValue),
    array: <N extends AnyNode>(...items: N[]) => node.array(items)
  };

  let memory = $state({
    i: dt.int(0),
    j: dt.int(0),
    arr: dt.array(dt.int(7), dt.int(2), dt.int(5), dt.int(2), dt.int(4), dt.int(1)),
    n: dt.int(6)
  });

  type Memory = typeof memory;

  type ExecUnit<T> = () => Generator<void, T, typeof memory>;
  type Mutation = ExecUnit<void>;
  type Expression<T> = ExecUnit<T>;

  // type ValueOf<T> = T[keyof T];

  // interface ExecNode {
  //   type: 'mutation' | 'predicate';
  //   description: string;
  // }

  function* program() {
    const _step = (f: (m: Memory) => void): Mutation =>
      function* () {
        f(memory);
      };

    const _set = <K extends keyof Memory>(
      name: K,
      valueExpr: Expression<Memory[K]['data']>
    ): Mutation =>
      function* () {
        const value = yield* valueExpr();
        memory[name].data = value;
      };

    const _value = <K extends keyof Memory>(name: K): Expression<Memory[K]['data']> =>
      function* () {
        return memory[name].data;
      };

    const _at = <N extends AnyNode>(
      arrayExpr: Expression<N[]>,
      indexExpr: Expression<number>
    ): Expression<N> =>
      function* () {
        const arrayNode = yield* arrayExpr();
        const index = yield* indexExpr();
        return arrayNode[index];
      };

    const _data = <N extends AnyNode>(nodeExpr: Expression<N>): Expression<N['data']> =>
      function* () {
        const node = yield* nodeExpr();
        return node.data;
      };

    const _literal = <T,>(value: T): Expression<T> =>
      function* () {
        return value;
      };

    const _add = (lhs: Expression<number>, rhs: Expression<number>): Expression<number> =>
      function* () {
        const lhsResult = yield* lhs();
        const rhsResult = yield* rhs();
        return lhsResult + rhsResult;
      };

    const _lt = (lhs: Expression<number>, rhs: Expression<number>): Expression<boolean> =>
      function* () {
        const lhsResult = yield* lhs();
        const rhsResult = yield* rhs();
        return lhsResult < rhsResult;
      };

    const _gt = (lhs: Expression<number>, rhs: Expression<number>): Expression<boolean> =>
      function* () {
        const lhsResult = yield* lhs();
        const rhsResult = yield* rhs();
        return lhsResult > rhsResult;
      };

    const _and = (lhs: Expression<boolean>, rhs: Expression<boolean>): Expression<boolean> =>
      function* () {
        const lhsResult = yield* lhs();
        if (!lhsResult) return false;
        const rhsResult = yield* rhs();
        return rhsResult;
      };

    const _for = (
      init: Mutation,
      condition: Expression<boolean>,
      update: Mutation,
      body: Mutation
    ): Mutation =>
      function* () {
        yield* init();
        while (yield* condition()) {
          yield* body();
          yield* update();
        }
      };

    const _while = (condition: Expression<boolean>, body: Mutation): Mutation =>
      function* () {
        while (yield* condition()) {
          yield* body();
        }
      };

    const _sequence = (...steps: Mutation[]): Mutation =>
      function* () {
        for (const step of steps) {
          yield* step();
        }
      };

    const _annotate = <T,>(
      selections: Record<string, (m: Memory) => AnyNode[]>,
      execUnit: ExecUnit<T>
    ): ExecUnit<T> =>
      function* () {
        const revertFns: Array<() => void> = [];

        Object.entries(selections).forEach(([key, fn]) => {
          const nodes = fn(memory);
          flatApplyNodes(nodes).forEach((node) => {
            node.annotations.push(key);
            revertFns.push(() => {
              node.annotations.pop();
            });
          });
        });

        yield;
        const result = yield* execUnit();

        revertFns.forEach((revert) => revert());

        return result;
      };

    const run = (m: Mutation) => m();

    return yield* run(
      _for(
        _set('i', _literal(1)),
        _lt(_value('i'), _value('n')),
        _set('i', _add(_value('i'), _literal(1))),
        _annotate(
          {
            sorted: (m) => m.arr.data.filter((_, idx) => idx < m.i.data),
            unsorted: (m) => m.arr.data.filter((_, idx) => idx >= m.i.data)
          },
          _sequence(
            _set('j', _value('i')),
            _annotate(
              {
                current: (m) => [m.arr.data[m.i.data]]
              },
              _while(
                _and(
                  _gt(_value('j'), _literal(0)),
                  _lt(
                    _data(_at(_value('arr'), _value('j'))),
                    _data(_at(_value('arr'), _add(_value('j'), _literal(-1))))
                  )
                ),
                _sequence(
                  _annotate(
                    {
                      comparing: (m) => [m.arr.data[m.j.data], m.arr.data[m.j.data - 1]]
                    },
                    _step((m) => {
                      const tmp = m.arr.data[m.j.data];
                      m.arr.data[m.j.data] = m.arr.data[m.j.data - 1];
                      m.arr.data[m.j.data - 1] = tmp;
                    })
                  ),
                  _set('j', _add(_value('j'), _literal(-1)))
                )
              )
            )
          )
        )
      )
    );

    // void insertion_sort(int a[], int n) {
    //     for (int i = 1; i < n; i++) {
    //         int j = i;
    //         while (j > 0 && a[j] < a[j - 1]) {
    //             int tmp = a[j];
    //             a[j] = a[j - 1];
    //             a[j - 1] = tmp;
    //             j--;
    //         }
    //     }
    // }
  }

  const steps = program();
  const nextStep = () => {
    const result = steps.next();
    console.log('STEP', result);
    if (result.done) {
      console.log('Program finished');
    }
  };
</script>

{#snippet nodeView(node: AnyNode)}
  <div class="node">
    {#if node.type === 'int'}
      <div class="dt-int {node.annotations.join(' ')}">
        {node.data}
      </div>
      <style>
        .dt-int {
          width: 50px;
          height: 50px;
          display: flex;
          align-items: center;
          justify-content: center;
          border: 2px solid #333;
          transition: background-color 0.5s ease;
        }

        .sorted {
          background-color: #a0e0a0;
        }

        .unsorted {
          background-color: #e0a0a0;
        }

        .current {
          background-color: #a0a0e0;
        }

        .comparing {
          background-color: #e0e0a0;
          border: 4px solid #333;
        }
      </style>
    {/if}
  </div>
{/snippet}

{#snippet arrayView(items: ArrayNode<AnyNode>)}
  <div class="array">
    {#each items.data as node, idx (node.id)}
      <div
        animate:flip={{ duration: 500 }}
        class="item"
        style:transform={`translateX(${idx * 70}px)`}
      >
        {@render nodeView(node)}
      </div>
    {/each}
  </div>
  <style>
    .array {
      position: relative;
      height: 50px;
    }
    .item {
      position: absolute;
      /* transition: transform 1s ease-in-out; */
    }
  </style>
{/snippet}

<div class="canvas">
  {@render arrayView(memory.arr)}
  <button class="button" onclick={nextStep}>Next Step</button>
</div>

<style>
  .canvas {
    display: flex;
    flex-direction: column;
    gap: 20px;
    margin: 40px;
    font-size: 24pt;
  }

  .button {
    padding: 10px 20px;
    font-size: 16pt;
    border: 2px solid #333;
  }
</style>
