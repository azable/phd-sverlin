import { describe, expect, it } from 'vitest';

import {
  algorithmLimits,
  interpretAlgorithm,
  interpretDesign,
  interpretInput,
  seededRandom
} from './interpret.server';

describe('algorithm interpretation', () => {
  it('records every top-level binding at each yield', () => {
    const trace = interpretAlgorithm(`
      const values = [3, 8, 5];
      let i = -1;
      let found = false;
      yield 'Start';
      for (i = 0; i < values.length; i++) {
        yield \`Compare \${values[i]}\`;
        if (values[i] === 8) {
          found = true;
          yield 'Found';
          break;
        }
      }
    `);
    expect(trace.map(({ label }) => label)).toEqual(['Start', 'Compare 3', 'Compare 8', 'Found']);
    expect(trace[0].state).toEqual({ values: [3, 8, 5], i: -1, found: false });
    expect(trace[3].state).toEqual({ values: [3, 8, 5], i: 1, found: true });
  });

  it('snapshots state so later mutations do not change earlier steps', () => {
    const trace = interpretAlgorithm(`
      const a = [2, 1];
      yield 'Before';
      const t = a[0]; a[0] = a[1]; a[1] = t;
      yield 'After';
    `);
    expect(trace[0].state.a).toEqual([2, 1]);
    expect(trace[1].state.a).toEqual([1, 2]);
    expect(trace[0].state.t).toBeNull();
  });

  it('supports loops, objects, array methods, Math, and early return', () => {
    const trace = interpretAlgorithm(`
      const stack = [];
      const point = { x: 1, y: 2 };
      let total = 0;
      for (const n of [4, 9, 16]) { stack.push(Math.sqrt(n)); total += n; }
      let k = 0;
      while (true) { k++; if (k > 2) break; else continue; }
      point.x += stack.indexOf(3);
      let i = 0;
      const a = [0, 0];
      a[i++] += 5;
      yield stack.join('-');
      return;
      yield 'Unreachable';
    `);
    expect(trace).toEqual([
      {
        label: '2-3-4',
        state: { stack: [2, 3, 4], point: { x: 2, y: 2 }, total: 29, k: 3, i: 1, a: [5, 0] }
      }
    ]);
  });

  it.each([
    ['functions', 'function f() {} yield "A";', /Function Declaration is not supported/],
    ['arrow functions', 'const f = () => 1; yield "A";', /Arrow Function Expression/],
    ['global access', 'const w = globalThis; yield "A";', /"globalThis" is not defined/],
    ['constructor escapes', 'const a = []; const c = a.constructor; yield "A";', /not allowed/],
    ['prototype keys', 'const o = {}; o["__proto__"] = 1; yield "A";', /not allowed/],
    ['host methods', 'const s = "x"; yield s.repeat(3);', /only available on arrays/],
    ['new', 'const d = new Date(); yield "A";', /New Expression/],
    ['loose equality', 'yield 1 == 1 ? "A" : "B";', /Use ===/],
    ['reserved names', 'let step = 0; yield "A";', /reserved/],
    ['undeclared assignment', 'x = 1; yield "A";', /must be declared/],
    ['no steps', 'let x = 1;', /at least one step/],
    ['non-string labels', 'yield 3;', /non-empty strings/],
    ['nested yield', 'const a = [yield "A"];', /statement of its own/],
    ['object arithmetic', 'const o = {}; yield "A" + (o - 1);', /Expected a number/]
  ])('rejects %s', (_name, body, message) => {
    expect(() => interpretAlgorithm(body)).toThrow(message);
  });

  it('stops endless loops and oversized state', () => {
    expect(() => interpretAlgorithm('while (true) {} yield "A";')).toThrow(/operations/);
    expect(() =>
      interpretAlgorithm('let s = "ab"; while (true) { s = s + s; } yield "A";')
    ).toThrow(/characters/);
    expect(() =>
      interpretAlgorithm('let a = [1]; while (true) { a = [...a, ...a]; } yield "A";')
    ).toThrow(/entries/);
    expect(() =>
      interpretAlgorithm('let a = [1, 2]; for (let i = 0; i < 40; i++) { a = [a, a]; } yield "A";')
    ).toThrow(/too large/);
    expect(() =>
      interpretAlgorithm(
        `for (let i = 0; i <= ${algorithmLimits.maximumSteps}; i++) yield \`S\${i}\`;`
      )
    ).toThrow(/more than/);
  });

  it('reports offsets into the algorithm body', () => {
    const body = 'let x = 1;\nyield "A";\nx = y;';
    expect(() => interpretAlgorithm(body)).toThrow(
      expect.objectContaining({ offset: body.indexOf('y;') })
    );
    expect(() => interpretAlgorithm('let x = ;')).toThrow(
      expect.objectContaining({ name: 'AlgorithmError', offset: 8 })
    );
  });
});

describe('input, design, and step selection', () => {
  it('starts the algorithm from the input and records input variables', () => {
    const input = interpretInput('const values = [2, 1]; const label = "pair";');
    const trace = interpretAlgorithm(
      'yield "Start"; values.reverse(); let swapped = true; yield "Swapped";',
      input
    );
    expect(trace.map(({ state }) => state)).toEqual([
      { values: [2, 1], label: 'pair', swapped: null },
      { values: [1, 2], label: 'pair', swapped: true }
    ]);
    expect(input.values).toEqual([2, 1]);
    expect(() => interpretAlgorithm('let values = []; yield "A";', input)).toThrow(
      /already declared here or in the input/
    );
    expect(() => interpretInput('const x = 1; yield "A";')).toThrow(/algorithm block/);
  });

  it('draws design values deterministically from the seed', () => {
    const body =
      'const layout = pick(["row", "grid", "stack"]); const size = int(3, 6); const scale = real(0.5, 1.5); const bold = chance(0.5); const doubled = size * 2;';
    const first = interpretDesign(body, 42);
    expect(interpretDesign(body, 42)).toEqual(first);
    expect(['row', 'grid', 'stack']).toContain(first.layout);
    expect(first.size).toBeGreaterThanOrEqual(3);
    expect(first.size).toBeLessThanOrEqual(6);
    expect(first.doubled).toBe((first.size as number) * 2);
    const layouts = new Set(
      Array.from({ length: 30 }, (_, seed) => interpretDesign(body, seed + 1).layout)
    );
    expect(layouts.size).toBe(3);
  });

  it.each([
    ['draws outside the design block', () => interpretAlgorithm('const a = pick([1]); yield "A";')],
    ['draws not assigned to a top-level const', () => interpretDesign('let a = pick([1]);', 1)],
    ['nested draws', () => interpretDesign('const a = [pick([1])];', 1)],
    ['draws inside blocks', () => interpretDesign('if (true) { const a = int(1, 2); }', 1)],
    ['removed optional yields', () => interpretAlgorithm('yield optional("x");')],
    ['unknown functions', () => interpretDesign('const a = shuffle([1]);', 1)]
  ])('rejects %s', (_name, run) => {
    expect(run).toThrow(/design draw|not available/);
  });

  it('validates draw arguments', () => {
    expect(() => interpretDesign('const a = int(5, 1);', 1)).toThrow(/minimum ≤ maximum/);
    expect(() => interpretDesign('const a = int(1.5, 3);', 1)).toThrow(/integers/);
    expect(() => interpretDesign('const a = pick([]);', 1)).toThrow(/non-empty array/);
  });

  it('requires unique step labels', () => {
    expect(() => interpretAlgorithm('for (let i = 0; i < 2; i++) yield "Compare";')).toThrow(
      /must be unique.*Compare/
    );
  });

  it('generates values in [0, 1) that depend on seed and stream', () => {
    const values = Array.from({ length: 1000 }, seededRandom(9, 1));
    expect(values.every((value) => value >= 0 && value < 1)).toBe(true);
    expect(seededRandom(9, 1)()).toBe(values[0]);
    expect(seededRandom(9, 2)()).not.toBe(values[0]);
    expect(seededRandom(10, 1)()).not.toBe(values[0]);
  });
});
