/** The domain block: atomic type definitions built from primitive kinds, refinements, and enumerations. */

import type { AnyNode, CallExpression, Expression, Pattern } from 'acorn';

import { atomBases, type AtomBase, type AtomRegistry, type AtomType } from './atoms.server';
import { AlgorithmError } from './block.server';
import { parseBlock } from './parse.server';

/**
 * Read the domain block's atomic type definitions. Nothing is predefined: a type is a primitive
 * kind (`type('integer')`), a refinement of a defined type (`type(Int, { unit: 'cm' })`), or an
 * enumeration (`type(['♠', '♥'])`).
 */
export function interpretDomain(body: string): AtomRegistry {
  const { root, offset } = parseBlock(body, 'domain');
  const fail = (node: AnyNode, message: string): never => {
    throw new AlgorithmError(message, offset(node));
  };
  const atoms: Record<string, AtomType> = {};
  for (const statement of root.body) {
    // The parsing wrapper's 'use strict' directive is not part of the authored block.
    if (statement.type === 'ExpressionStatement' && 'directive' in statement) continue;
    if (statement.type !== 'VariableDeclaration' || statement.kind !== 'const')
      fail(statement, 'The domain block only defines types, as in const Height = type(Int);');
    for (const declarator of (statement as { declarations: { id: Pattern; init?: unknown }[] })
      .declarations) {
      const name = (declarator.id as { name: string }).name;
      const init = declarator.init as Expression | undefined | null;
      if (init?.type !== 'CallExpression' || (init.callee as { name?: string }).name !== 'type')
        fail(
          declarator as AnyNode,
          `Define ${name} with type(...), as in const ${name} = type(Int);`
        );
      const call = init as CallExpression;
      if (name in atoms) fail(declarator as AnyNode, `"${name}" is already a type.`);
      const [definition, options, extra] = call.arguments as Expression[];
      if (!definition || extra)
        fail(
          call,
          'type() takes a kind, a type, or a list of allowed values, then optional options.'
        );
      let type: AtomType;
      if (definition.type === 'Literal' && typeof definition.value === 'string') {
        if (!atomBases.includes(definition.value as AtomBase))
          fail(
            definition,
            `Unknown kind "${definition.value}"; use one of ${atomBases.join(', ')}.`
          );
        type = { name, base: definition.value as AtomBase };
      } else if (definition.type === 'Identifier') {
        const parent = atoms[definition.name];
        if (!parent)
          fail(
            definition,
            `Unknown type ${definition.name}; define it first, as in const ${definition.name} = type('integer');`
          );
        type = { ...parent, name, parent: parent.name };
      } else if (definition.type === 'ArrayExpression') {
        const values = definition.elements.map((element) => {
          const value = element ? literalValue(element as Expression) : undefined;
          if (typeof value !== 'string' && typeof value !== 'number')
            fail(element ?? definition, 'Enumeration values must be text or number literals.');
          return value as string | number;
        });
        if (values.length === 0 || new Set(values).size !== values.length)
          fail(definition, 'An enumeration needs at least one value, each listed once.');
        const base: AtomBase = values.every((value) => typeof value === 'string')
          ? 'text'
          : values.every((value) => typeof value === 'number')
            ? values.every(Number.isInteger)
              ? 'integer'
              : 'number'
            : fail(definition, 'Enumeration values must be all text or all numbers.');
        type = { name, base, values };
      } else {
        type = fail(
          definition,
          `type() takes a kind such as 'integer', a defined type, or a list of allowed values.`
        );
      }
      if (options) applyAtomOptions(type, options, fail);
      atoms[name] = type;
    }
  }
  return atoms;
}

function applyAtomOptions(
  type: AtomType,
  options: Expression,
  fail: (node: AnyNode, message: string) => never
): void {
  if (options.type !== 'ObjectExpression')
    fail(options, 'type() options are an object such as { unit: "cm", min: 0 }.');
  for (const property of (options as { properties: AnyNode[] }).properties) {
    if (property.type !== 'Property' || property.key.type !== 'Identifier')
      fail(property, 'type() options are plain name: value pairs.');
    const { key, value } = property as unknown as { key: { name: string }; value: Expression };
    const literal = literalValue(value);
    if (key.name === 'unit') {
      if (typeof literal !== 'string' || !literal.trim()) fail(value, 'unit must be text.');
      type.unit = literal as string;
    } else if (key.name === 'min' || key.name === 'max') {
      if (type.base !== 'integer' && type.base !== 'number')
        fail(property, `${key.name} only applies to integer and number types.`);
      if (typeof literal !== 'number' || !Number.isFinite(literal))
        fail(value, `${key.name} must be a number.`);
      type[key.name] = literal as number;
    } else {
      fail(property, `Unknown type() option "${key.name}"; use unit, min, or max.`);
    }
  }
  if (type.min !== undefined && type.max !== undefined && type.min > type.max)
    fail(options, 'min must not exceed max.');
}

/** A literal's value, including negative numbers; undefined for anything else. */
function literalValue(node: Expression): unknown {
  if (node.type === 'Literal') return node.value;
  if (node.type === 'UnaryExpression' && node.operator === '-' && node.argument.type === 'Literal')
    return typeof node.argument.value === 'number' ? -node.argument.value : undefined;
  return undefined;
}
