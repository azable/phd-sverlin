/** Parse, restrict, and interpret Sverlin input, design, and algorithm blocks. */

import {
  parse,
  type AnyNode,
  type BlockStatement,
  type CallExpression,
  type Expression,
  type FunctionDeclaration,
  type MemberExpression,
  type Pattern,
  type SpreadElement,
  type Statement
} from 'acorn';

/** JSON-compatible state recorded for one step and passed to the view as props. */
export type TraceValue =
  | null
  | boolean
  | number
  | string
  | TraceValue[]
  | { [key: string]: TraceValue };

export type TraceState = Record<string, TraceValue>;

/** One uniquely labelled step of the master trace that every presentation of a source shares. */
export type MasterStep = {
  label: string;
  state: TraceState;
};

/** Input: fixed initial state. Design: seeded presentation choices. Algorithm: the yielding steps. */
export type BlockKind = 'input' | 'design' | 'algorithm';

// Bounds keep interpretation short, memory small, and the embedded trace well inside the bundle limit.
export const algorithmLimits = {
  maximumSteps: 200,
  maximumOperations: 1_000_000,
  maximumCollectionLength: 10_000,
  maximumStringLength: 10_000,
  maximumTraceValues: 200_000
} as const;

/** Names the view receives from the application rather than from the algorithm. */
const reservedNames = new Set(['step', 'seed']);
const forbiddenProperties = new Set(['__proto__', 'prototype', 'constructor']);

export class AlgorithmError extends Error {
  /** Offset into the algorithm body, when known. */
  readonly offset?: number;

  constructor(message: string, offset?: number) {
    super(message);
    this.name = 'AlgorithmError';
    if (offset !== undefined) this.offset = offset;
  }
}

// A strict-mode generator wrapper lets acorn parse top-level yield; it shares the body's first line.
const wrapperPrefix = "function* algorithm() {'use strict';";

/** Interpret the input block into the fixed initial state shared by every presentation. */
export function interpretInput(body: string): TraceState {
  const { root, offset } = parseBlock(body, 'input');
  return new Interpreter(root, offset, { kind: 'input' }).bindings();
}

/** Interpret the design block with draws from the presentation seed. */
export function interpretDesign(body: string, seed: number): TraceState {
  const { root, offset } = parseBlock(body, 'design');
  return new Interpreter(root, offset, {
    kind: 'design',
    random: seededRandom(seed, designStream)
  }).bindings();
}

/** Names a block declares at its top level, read without running it. */
export function declaredNames(body: string, kind: BlockKind): string[] {
  const { root } = parseBlock(body, kind);
  return root.body.flatMap((statement) =>
    statement.type === 'VariableDeclaration'
      ? statement.declarations.map((declarator) => (declarator.id as { name: string }).name)
      : []
  );
}

/** Interpret the algorithm from the input state; every top-level binding is recorded at each yield. */
export function interpretAlgorithm(body: string, input: TraceState = {}): MasterStep[] {
  const { root, offset } = parseBlock(body, 'algorithm');
  return new Interpreter(root, offset, { kind: 'algorithm', initial: input }).run();
}

// Changing this generator or its stream changes every rebuilt presentation; version it if needed.
const designStream = 1;

/** Deterministic splitmix32-style generator for one seed and stream, returning values in [0, 1). */
export function seededRandom(seed: number, stream: number): () => number {
  let state = (Math.imul(seed >>> 0, 0x9e3779b1) ^ Math.imul(stream, 0x85ebca77)) >>> 0;
  return () => {
    state = (state + 0x9e3779b9) | 0;
    let mixed = Math.imul(state ^ (state >>> 16), 0x85ebca6b);
    mixed = Math.imul(mixed ^ (mixed >>> 13), 0xc2b2ae35);
    return ((mixed ^ (mixed >>> 16)) >>> 0) / 4294967296;
  };
}

function parseBlock(
  body: string,
  kind: BlockKind
): { root: BlockStatement; offset: (node: AnyNode) => number } {
  let program;
  try {
    program = parse(`${wrapperPrefix}${body}\n}`, { ecmaVersion: 2022, sourceType: 'script' });
  } catch (cause) {
    const position = (cause as { pos?: unknown }).pos;
    const message = cause instanceof Error ? cause.message : String(cause);
    throw new AlgorithmError(
      message.replace(/\s*\(\d+:\d+\)$/u, ''),
      typeof position === 'number'
        ? Math.min(Math.max(position - wrapperPrefix.length, 0), body.length)
        : undefined
    );
  }
  const root = (program.body[0] as FunctionDeclaration).body;
  const offset = (node: AnyNode) => node.start - wrapperPrefix.length;
  checkSubset(root, offset, kind);
  return { root, offset };
}

// ---------------------------------------------------------------------------------------------
// Static subset check: everything outside this list is rejected before any statement runs.

const allowedBinary = new Set(['+', '-', '*', '/', '%', '**', '<', '<=', '>', '>=', '===', '!==']);
const allowedAssignment = new Set(['=', '+=', '-=', '*=', '/=', '%=']);

function checkSubset(
  root: BlockStatement,
  offset: (node: AnyNode) => number,
  kind: BlockKind
): void {
  const reject = (node: AnyNode, message: string): never => {
    throw new AlgorithmError(message, offset(node));
  };
  const visit = (node: AnyNode, ancestors: readonly AnyNode[]): void => {
    const parent = ancestors.at(-1);
    switch (node.type) {
      case 'BlockStatement':
      case 'ExpressionStatement':
      case 'IfStatement':
      case 'ForStatement':
      case 'WhileStatement':
      case 'DoWhileStatement':
      case 'EmptyStatement':
      case 'ArrayExpression':
      case 'SpreadElement':
      case 'ConditionalExpression':
      case 'LogicalExpression':
      case 'SequenceExpression':
      case 'TemplateLiteral':
      case 'TemplateElement':
      case 'VariableDeclarator':
      case 'ObjectExpression':
        break;
      case 'CallExpression':
        if (node.callee.type === 'Identifier') checkBuiltin(node, node.callee.name, ancestors);
        break;
      case 'ReturnStatement':
        if (node.argument) reject(node, 'return stops the algorithm and cannot return a value.');
        break;
      case 'BreakStatement':
      case 'ContinueStatement':
        if (node.label) reject(node, 'Labelled break and continue are not supported.');
        break;
      case 'VariableDeclaration':
        if (node.kind === 'var') reject(node, 'Use let or const instead of var.');
        for (const declarator of node.declarations) {
          if (declarator.id.type !== 'Identifier')
            reject(declarator, 'Destructuring declarations are not supported.');
          else if (reservedNames.has(declarator.id.name))
            reject(declarator, `"${declarator.id.name}" is reserved for the view.`);
        }
        break;
      case 'ForOfStatement':
        if (
          node.await ||
          node.left.type !== 'VariableDeclaration' ||
          node.left.declarations[0]?.id.type !== 'Identifier'
        )
          reject(node, 'for...of must declare one variable, as in for (const x of items).');
        break;
      case 'Identifier':
        break;
      case 'Literal':
        if ('regex' in node || 'bigint' in node)
          reject(node, 'Regular expressions and BigInt are not supported.');
        break;
      case 'Property':
        if (node.kind !== 'init' || node.method || node.computed)
          reject(node, 'Object properties must be plain name: value pairs.');
        if (
          (node.key.type === 'Identifier' && forbiddenProperties.has(node.key.name)) ||
          (node.key.type === 'Literal' && forbiddenProperties.has(String(node.key.value)))
        )
          reject(node, 'That property name is not allowed.');
        break;
      case 'MemberExpression':
        if (node.optional) reject(node, 'Optional chaining is not supported.');
        if (node.object.type === 'Super') reject(node, 'super is not supported.');
        if (!node.computed && node.property.type === 'Identifier') {
          if (forbiddenProperties.has(node.property.name))
            reject(node, 'That property name is not allowed.');
        }
        break;
      case 'UnaryExpression':
        if (!['!', '-', '+'].includes(node.operator))
          reject(node, `The ${node.operator} operator is not supported.`);
        break;
      case 'BinaryExpression':
        if (node.operator === '==' || node.operator === '!=')
          reject(node, `Use ${node.operator}= instead of ${node.operator}.`);
        if (!allowedBinary.has(node.operator))
          reject(node, `The ${node.operator} operator is not supported.`);
        break;
      case 'AssignmentExpression':
        if (!allowedAssignment.has(node.operator))
          reject(node, `The ${node.operator} operator is not supported.`);
        if (node.left.type !== 'Identifier' && node.left.type !== 'MemberExpression')
          reject(node, 'Only variables, elements, and properties can be assigned.');
        break;
      case 'UpdateExpression':
        if (node.argument.type !== 'Identifier' && node.argument.type !== 'MemberExpression')
          reject(node, 'Only variables, elements, and properties can be incremented.');
        break;
      case 'YieldExpression':
        if (kind !== 'algorithm')
          reject(node, `yield belongs in the algorithm block, not the ${kind} block.`);
        if (node.delegate) reject(node, 'yield* is not supported.');
        if (parent?.type !== 'ExpressionStatement')
          reject(node, 'yield must be a statement of its own, as in yield "label";');
        break;
      default:
        reject(node, `${describe(node.type)} is not supported in ${kind} blocks.`);
    }
    for (const [key, child] of Object.entries(node)) {
      if (key === 'loc') continue;
      for (const item of Array.isArray(child) ? child : [child]) {
        if (item && typeof item === 'object' && typeof (item as AnyNode).type === 'string')
          visit(item as AnyNode, [...ancestors, node]);
      }
    }
  };
  const checkBuiltin = (node: AnyNode, name: string, ancestors: readonly AnyNode[]): void => {
    const [declaration, declarator] = ancestors.slice(-2);
    if (drawFunctions.has(name)) {
      if (
        kind !== 'design' ||
        ancestors.length !== 3 ||
        declaration.type !== 'VariableDeclaration' ||
        declaration.kind !== 'const' ||
        declarator.type !== 'VariableDeclarator' ||
        declarator.init !== node
      )
        reject(
          node,
          `${name}() is a design draw; use it only as const name = ${name}(...) at the top of the design block.`
        );
    } else {
      reject(
        node,
        `${name}() is not available; only Math functions and array methods can be called.`
      );
    }
  };
  root.body.forEach((statement) => visit(statement, [root]));
}

const drawFunctions = new Set(['pick', 'int', 'real', 'chance']);

function describe(type: string): string {
  return type.replace(/([a-z])([A-Z])/gu, '$1 $2').replace(/^./u, (first) => first.toUpperCase());
}

// ---------------------------------------------------------------------------------------------
// Interpreter: values are primitives, plain arrays, and null-prototype objects created here.

type ObjectValue = { [key: string]: Value };
type Value = undefined | null | boolean | number | string | Value[] | ObjectValue;
type Binding = { value: Value; constant: boolean };
type Completion = 'normal' | 'break' | 'continue' | 'return';

const mathFunctions: Record<string, (...values: number[]) => number> = {
  abs: Math.abs,
  ceil: Math.ceil,
  floor: Math.floor,
  max: Math.max,
  min: Math.min,
  pow: Math.pow,
  round: Math.round,
  sign: Math.sign,
  sqrt: Math.sqrt,
  trunc: Math.trunc
};
const mathConstants: Record<string, number> = { PI: Math.PI, E: Math.E };
const mathMarker = Object.freeze(Object.create(null)) as ObjectValue;

class Scope {
  readonly bindings = new Map<string, Binding>();
  constructor(readonly parent?: Scope) {}

  lookup(name: string): Binding | undefined {
    return this.bindings.get(name) ?? this.parent?.lookup(name);
  }
}

class Interpreter {
  readonly #root: BlockStatement;
  readonly #offset: (node: AnyNode) => number;
  readonly #globals = new Scope();
  readonly #topLevel = new Scope(this.#globals);
  readonly #topLevelNames: string[];
  readonly #kind: BlockKind;
  readonly #random?: () => number;
  readonly #trace: MasterStep[] = [];
  readonly #labels = new Set<string>();
  #operations = 0;
  #traceValues = 0;

  constructor(
    root: BlockStatement,
    offset: (node: AnyNode) => number,
    options: { kind: BlockKind; initial?: TraceState; random?: () => number }
  ) {
    this.#root = root;
    this.#offset = offset;
    this.#kind = options.kind;
    this.#random = options.random;
    this.#globals.bindings.set('Math', { value: mathMarker, constant: true });
    this.#globals.bindings.set('undefined', { value: undefined, constant: true });
    this.#globals.bindings.set('Infinity', { value: Infinity, constant: true });
    this.#globals.bindings.set('NaN', { value: NaN, constant: true });
    // Input values become ordinary top-level variables the algorithm may update.
    const initial = Object.entries(options.initial ?? {});
    for (const [name, value] of initial)
      this.#topLevel.bindings.set(name, { value: fromTrace(value), constant: false });
    this.#topLevelNames = [
      ...initial.map(([name]) => name),
      ...root.body.flatMap((statement) =>
        statement.type === 'VariableDeclaration'
          ? statement.declarations.map((declarator) => (declarator.id as { name: string }).name)
          : []
      )
    ];
  }

  /** Run the algorithm block and return its master trace. */
  run(): MasterStep[] {
    this.#execute();
    if (this.#trace.length === 0)
      throw new AlgorithmError('The algorithm must yield at least one step, as in yield "Start";');
    return this.#trace;
  }

  /** Run a input or design block and return its top-level bindings. */
  bindings(): TraceState {
    this.#execute();
    return this.#state(this.#root);
  }

  #execute(): void {
    const completion = this.#block(this.#root.body, this.#topLevel);
    if (completion === 'break' || completion === 'continue')
      throw new AlgorithmError(`${completion} must be inside a loop.`, this.#offset(this.#root));
    if (completion === 'return' && this.#kind !== 'algorithm')
      throw new AlgorithmError(`return belongs in the algorithm block.`, this.#offset(this.#root));
  }

  #state(node: AnyNode): TraceState {
    const state: TraceState = {};
    for (const name of this.#topLevelNames) {
      const binding = this.#topLevel.bindings.get(name);
      state[name] = binding ? this.#snapshot(binding.value, node) : null;
    }
    return state;
  }

  #fail(node: AnyNode, message: string): never {
    throw new AlgorithmError(message, this.#offset(node));
  }

  #charge(node: AnyNode, amount = 1): void {
    this.#operations += amount;
    if (this.#operations > algorithmLimits.maximumOperations)
      this.#fail(
        node,
        `The algorithm exceeded ${algorithmLimits.maximumOperations} operations; check for an endless loop or reduce the input.`
      );
  }

  #block(statements: readonly Statement[], scope: Scope): Completion {
    for (const statement of statements) {
      const completion = this.#statement(statement, scope);
      if (completion !== 'normal') return completion;
    }
    return 'normal';
  }

  #statement(node: Statement, scope: Scope): Completion {
    this.#charge(node);
    switch (node.type) {
      case 'BlockStatement':
        return this.#block(node.body, new Scope(scope));
      case 'EmptyStatement':
        return 'normal';
      case 'ExpressionStatement':
        if (node.expression.type === 'YieldExpression') {
          this.#yield(node.expression.argument ?? undefined, node, scope);
        } else {
          this.#expression(node.expression, scope);
        }
        return 'normal';
      case 'VariableDeclaration':
        for (const declarator of node.declarations) {
          const name = (declarator.id as { name: string }).name;
          if (scope.bindings.has(name))
            this.#fail(
              declarator,
              this.#kind === 'algorithm' && scope === this.#topLevel
                ? `"${name}" is already declared here or in the input block.`
                : `"${name}" is already declared.`
            );
          const value = declarator.init ? this.#expression(declarator.init, scope) : undefined;
          scope.bindings.set(name, { value, constant: node.kind === 'const' });
        }
        return 'normal';
      case 'IfStatement':
        if (this.#expression(node.test, scope)) return this.#statement(node.consequent, scope);
        return node.alternate ? this.#statement(node.alternate, scope) : 'normal';
      case 'WhileStatement':
        while (this.#expression(node.test, scope)) {
          const completion = this.#statement(node.body, scope);
          if (completion === 'return') return completion;
          if (completion === 'break') break;
        }
        return 'normal';
      case 'DoWhileStatement':
        do {
          const completion = this.#statement(node.body, scope);
          if (completion === 'return') return completion;
          if (completion === 'break') break;
        } while (this.#expression(node.test, scope));
        return 'normal';
      case 'ForStatement': {
        const loopScope = new Scope(scope);
        if (node.init) {
          if (node.init.type === 'VariableDeclaration') this.#statement(node.init, loopScope);
          else this.#expression(node.init, loopScope);
        }
        while (!node.test || this.#expression(node.test, loopScope)) {
          const completion = this.#statement(node.body, loopScope);
          if (completion === 'return') return completion;
          if (completion === 'break') break;
          if (node.update) this.#expression(node.update, loopScope);
          this.#charge(node);
        }
        return 'normal';
      }
      case 'ForOfStatement': {
        const items = this.#expression(node.right as Expression, scope);
        if (!Array.isArray(items)) this.#fail(node.right, 'for...of can only iterate over arrays.');
        const declaration = node.left as { kind: string; declarations: { id: Pattern }[] };
        const name = (declaration.declarations[0].id as { name: string }).name;
        for (let index = 0; index < items.length; index++) {
          const loopScope = new Scope(scope);
          loopScope.bindings.set(name, {
            value: items[index],
            constant: declaration.kind === 'const'
          });
          const completion = this.#statement(node.body, loopScope);
          if (completion === 'return') return completion;
          if (completion === 'break') break;
        }
        return 'normal';
      }
      case 'ReturnStatement':
        return 'return';
      case 'BreakStatement':
        return 'break';
      case 'ContinueStatement':
        return 'continue';
      default:
        return this.#fail(node, `${describe(node.type)} is not supported in algorithm blocks.`);
    }
  }

  #yield(argument: Expression | undefined, node: AnyNode, scope: Scope): void {
    const label =
      argument === undefined ? `Step ${this.#trace.length + 1}` : this.#expression(argument, scope);
    if (typeof label !== 'string' || !label.trim())
      this.#fail(node, 'yield labels must be non-empty strings.');
    const trimmed = label.trim();
    if (this.#labels.has(trimmed))
      this.#fail(
        node,
        `Step labels must be unique, but "${trimmed}" was already used; include what distinguishes the step, such as \`Compare index \${i}\`.`
      );
    if (this.#trace.length >= algorithmLimits.maximumSteps)
      this.#fail(node, `The algorithm yielded more than ${algorithmLimits.maximumSteps} steps.`);
    this.#labels.add(trimmed);
    this.#trace.push({ label: trimmed, state: this.#state(node) });
  }

  /** Deep copy with a total node budget, which also stops shared structure from multiplying. */
  #snapshot(value: Value, node: AnyNode): TraceValue {
    this.#traceValues += 1;
    if (this.#traceValues > algorithmLimits.maximumTraceValues)
      this.#fail(node, 'The recorded steps are too large; use smaller state or fewer steps.');
    if (value === undefined) return null;
    if (Array.isArray(value)) return Array.from(value, (item) => this.#snapshot(item, node));
    if (value === mathMarker) return null;
    if (value !== null && typeof value === 'object') {
      const copy: Record<string, TraceValue> = {};
      for (const [key, item] of Object.entries(value)) copy[key] = this.#snapshot(item, node);
      return copy;
    }
    return typeof value === 'number' && !Number.isFinite(value) ? null : value;
  }

  #expression(node: Expression | SpreadElement, scope: Scope): Value {
    this.#charge(node);
    switch (node.type) {
      case 'Literal':
        return node.value as Value;
      case 'Identifier': {
        const binding = scope.lookup(node.name);
        if (!binding) this.#fail(node, `"${node.name}" is not defined.`);
        return binding.value;
      }
      case 'TemplateLiteral': {
        let text = node.quasis[0].value.cooked ?? '';
        node.expressions.forEach((expression, index) => {
          text += this.#text(this.#expression(expression, scope), expression);
          text += node.quasis[index + 1].value.cooked ?? '';
        });
        return this.#checkString(text, node);
      }
      case 'ArrayExpression': {
        const items: Value[] = [];
        for (const element of node.elements) {
          if (element === null) this.#fail(node, 'Array holes are not supported.');
          if (element.type === 'SpreadElement') {
            const spread = this.#expression(element.argument, scope);
            if (!Array.isArray(spread)) this.#fail(element, 'Only arrays can be spread.');
            this.#charge(element, spread.length);
            items.push(...spread);
          } else {
            items.push(this.#expression(element, scope));
          }
          this.#checkLength(items.length, node);
        }
        return items;
      }
      case 'ObjectExpression': {
        const object = Object.create(null) as ObjectValue;
        for (const property of node.properties) {
          if (property.type !== 'Property') this.#fail(property, 'Object spread is not supported.');
          const key =
            property.key.type === 'Identifier'
              ? property.key.name
              : String((property.key as { value?: unknown }).value);
          object[key] = this.#expression(property.value as Expression, scope);
        }
        return object;
      }
      case 'MemberExpression':
        return this.#read(this.#expression(node.object as Expression, scope), node, scope);
      case 'CallExpression':
        return this.#call(node, scope);
      case 'UnaryExpression': {
        const value = this.#expression(node.argument, scope);
        if (node.operator === '!') return !value;
        return node.operator === '-' ? -this.#number(value, node) : this.#number(value, node);
      }
      case 'BinaryExpression':
        return this.#binary(
          node.operator,
          this.#expression(node.left as Expression, scope),
          this.#expression(node.right, scope),
          node
        );
      case 'LogicalExpression': {
        const left = this.#expression(node.left, scope);
        if (node.operator === '&&') return left ? this.#expression(node.right, scope) : left;
        if (node.operator === '||') return left ? left : this.#expression(node.right, scope);
        return left ?? this.#expression(node.right, scope);
      }
      case 'ConditionalExpression':
        return this.#expression(node.test, scope)
          ? this.#expression(node.consequent, scope)
          : this.#expression(node.alternate, scope);
      case 'SequenceExpression': {
        let value: Value;
        for (const expression of node.expressions) value = this.#expression(expression, scope);
        return value;
      }
      case 'AssignmentExpression': {
        // Resolve the target once so a[i++] += 1 evaluates i++ a single time, as in JavaScript.
        const target = this.#reference(node.left as Expression, scope);
        const right = this.#expression(node.right, scope);
        const value =
          node.operator === '='
            ? right
            : this.#binary(node.operator.slice(0, -1), target.get(), right, node);
        target.set(value);
        return value;
      }
      case 'UpdateExpression': {
        const target = this.#reference(node.argument, scope);
        const before = this.#number(target.get(), node);
        const after = node.operator === '++' ? before + 1 : before - 1;
        target.set(after);
        return node.prefix ? after : before;
      }
      default:
        return this.#fail(node, `${describe(node.type)} is not supported in algorithm blocks.`);
    }
  }

  #reference(target: Expression, scope: Scope): { get(): Value; set(value: Value): void } {
    if (target.type === 'Identifier') {
      const binding = scope.lookup(target.name);
      if (!binding || binding === this.#globals.bindings.get(target.name))
        this.#fail(target, `"${target.name}" must be declared with let before it is assigned.`);
      if (binding.constant) this.#fail(target, `"${target.name}" is a constant.`);
      return {
        get: () => binding.value,
        set: (value) => {
          binding.value = value;
        }
      };
    }
    if (target.type !== 'MemberExpression') this.#fail(target, 'Invalid assignment target.');
    const object = this.#expression(target.object as Expression, scope);
    const key = this.#key(target, scope);
    if (Array.isArray(object)) {
      if (typeof key !== 'number' || !Number.isInteger(key) || key < 0)
        this.#fail(target, 'Array elements are assigned by non-negative integer index.');
      return {
        get: () => object[key],
        set: (value) => {
          this.#checkLength(key + 1, target);
          while (object.length < key) object.push(undefined);
          object[key] = value;
        }
      };
    }
    if (object === null || typeof object !== 'object' || object === mathMarker)
      this.#fail(target, 'Only arrays and objects can have elements or properties assigned.');
    const name = String(key);
    if (forbiddenProperties.has(name)) this.#fail(target, 'That property name is not allowed.');
    return {
      get: () => object[name],
      set: (value) => {
        if (!(name in object)) this.#checkLength(Object.keys(object).length + 1, target);
        object[name] = value;
      }
    };
  }

  #key(node: MemberExpression, scope: Scope): Value {
    if (!node.computed) return (node.property as { name: string }).name;
    const key = this.#expression(node.property as Expression, scope);
    if (typeof key !== 'number' && typeof key !== 'string')
      this.#fail(node.property, 'Indexes must be numbers or strings.');
    return key;
  }

  #read(object: Value, node: MemberExpression, scope: Scope): Value {
    const key = this.#key(node, scope);
    if (object === mathMarker) {
      if (typeof key === 'string' && key in mathConstants) return mathConstants[key];
      return this.#fail(node, `Math.${String(key)} can only be called, or does not exist.`);
    }
    if (Array.isArray(object) || typeof object === 'string') {
      if (key === 'length') return object.length;
      if (typeof key === 'number' && Number.isInteger(key) && key >= 0) return object[key];
      return this.#fail(node, `Unsupported element or property "${String(key)}".`);
    }
    if (object !== null && typeof object === 'object') {
      const name = String(key);
      if (forbiddenProperties.has(name)) this.#fail(node, 'That property name is not allowed.');
      return object[name];
    }
    return this.#fail(node, `Cannot read "${String(key)}" of ${String(object)}.`);
  }

  #call(node: CallExpression, scope: Scope): Value {
    const callee = node.callee;
    if (callee.type === 'Identifier' && this.#random && drawFunctions.has(callee.name))
      return this.#draw(callee.name, node, scope);
    if (callee.type !== 'MemberExpression' || callee.computed || node.optional)
      this.#fail(node, 'Only Math functions and array methods can be called.');
    const object = this.#expression(callee.object as Expression, scope);
    const name = (callee.property as { name: string }).name;
    const args = node.arguments.map((argument) => {
      if (argument.type === 'SpreadElement')
        this.#fail(argument, 'Spread arguments are not supported.');
      return this.#expression(argument, scope);
    });
    if (object === mathMarker) {
      const fn = mathFunctions[name];
      if (!fn) this.#fail(callee, `Math.${name} is not available.`);
      return fn(...args.map((argument) => this.#number(argument, node)));
    }
    if (!Array.isArray(object)) this.#fail(callee, `.${name}() is only available on arrays.`);
    this.#charge(node, object.length);
    switch (name) {
      case 'push':
        this.#checkLength(object.length + args.length, node);
        return object.push(...args);
      case 'pop':
        return object.pop();
      case 'shift':
        return object.shift();
      case 'unshift':
        this.#checkLength(object.length + args.length, node);
        return object.unshift(...args);
      case 'slice':
        return object.slice(
          args[0] === undefined ? undefined : this.#number(args[0], node),
          args[1] === undefined ? undefined : this.#number(args[1], node)
        );
      case 'indexOf':
        return object.indexOf(args[0]);
      case 'includes':
        return object.includes(args[0]);
      case 'reverse':
        return object.reverse();
      case 'join': {
        const separator = args[0] === undefined ? ',' : this.#text(args[0], node);
        return this.#checkString(
          object.map((item) => this.#text(item, node)).join(separator),
          node
        );
      }
      default:
        return this.#fail(callee, `Array method .${name}() is not available.`);
    }
  }

  /** Seeded design draws: pick(items), int(min, max) inclusive, real(min, max), chance(p). */
  #draw(name: string, node: CallExpression, scope: Scope): Value {
    const random = this.#random as () => number;
    const args = node.arguments.map((argument) => {
      if (argument.type === 'SpreadElement')
        this.#fail(argument, 'Spread arguments are not supported.');
      return this.#expression(argument, scope);
    });
    if (name === 'pick') {
      const [items] = args;
      if (!Array.isArray(items) || items.length === 0 || args.length !== 1)
        this.#fail(node, 'pick() takes one non-empty array of choices.');
      return items[Math.floor(random() * items.length)];
    }
    if (name === 'chance') {
      const probability = this.#number(args[0], node);
      if (args.length !== 1 || !(probability >= 0 && probability <= 1))
        this.#fail(node, 'chance() takes one probability from 0 to 1.');
      return random() < probability;
    }
    const [min, max] = args.map((argument) => this.#number(argument, node));
    if (args.length !== 2 || !Number.isFinite(min) || !Number.isFinite(max) || min > max)
      this.#fail(node, `${name}() takes a finite minimum and maximum, with minimum ≤ maximum.`);
    if (name === 'int') {
      if (!Number.isInteger(min) || !Number.isInteger(max))
        this.#fail(node, 'int() bounds must be integers.');
      return min + Math.floor(random() * (max - min + 1));
    }
    return min + random() * (max - min);
  }

  #binary(operator: string, left: Value, right: Value, node: AnyNode): Value {
    switch (operator) {
      case '===':
        return left === right;
      case '!==':
        return left !== right;
      case '+':
        if (typeof left === 'string' || typeof right === 'string')
          return this.#checkString(this.#text(left, node) + this.#text(right, node), node);
        return this.#number(left, node) + this.#number(right, node);
      case '<':
      case '<=':
      case '>':
      case '>=': {
        const bothStrings = typeof left === 'string' && typeof right === 'string';
        const a = bothStrings ? left : this.#number(left, node);
        const b = bothStrings ? right : this.#number(right, node);
        if (operator === '<') return a < b;
        if (operator === '<=') return a <= b;
        return operator === '>' ? a > b : a >= b;
      }
      default: {
        const a = this.#number(left, node);
        const b = this.#number(right, node);
        if (operator === '-') return a - b;
        if (operator === '*') return a * b;
        if (operator === '/') return a / b;
        if (operator === '%') return a % b;
        if (operator === '**') return a ** b;
        return this.#fail(node, `The ${operator} operator is not supported.`);
      }
    }
  }

  #number(value: Value, node: AnyNode): number {
    if (typeof value !== 'number') this.#fail(node, `Expected a number but found ${kind(value)}.`);
    return value;
  }

  #text(value: Value, node: AnyNode): string {
    if (value !== null && typeof value === 'object')
      this.#fail(node, `Cannot turn ${kind(value)} into text; use .join() for arrays.`);
    return String(value);
  }

  #checkString(text: string, node: AnyNode): string {
    if (text.length > algorithmLimits.maximumStringLength)
      this.#fail(node, `Strings are limited to ${algorithmLimits.maximumStringLength} characters.`);
    return text;
  }

  #checkLength(length: number, node: AnyNode): void {
    if (length > algorithmLimits.maximumCollectionLength)
      this.#fail(
        node,
        `Arrays and objects are limited to ${algorithmLimits.maximumCollectionLength} entries.`
      );
  }
}

function kind(value: Value): string {
  if (value === null) return 'null';
  if (Array.isArray(value)) return 'an array';
  return typeof value === 'object' ? 'an object' : typeof value;
}

/** Rebuild interpreter values from recorded input state, with null-prototype objects. */
function fromTrace(value: TraceValue): Value {
  if (Array.isArray(value)) return value.map(fromTrace);
  if (value !== null && typeof value === 'object') {
    const object = Object.create(null) as ObjectValue;
    for (const [key, item] of Object.entries(value)) object[key] = fromTrace(item);
    return object;
  }
  return value;
}
