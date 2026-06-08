import { Constraint, Variable } from './layout.svelte';

const VAR_PREFIX = '$';
const MAX_INLINE_WIDTH = 80;
const INDENT = '  ';

export const debugPrettyPrint = (obj: object, keyWidth: number = 0) => {
  const entries = Object.entries(obj);

  if (entries.length === 0) {
    return '<empty>';
  }

  keyWidth = Math.max(keyWidth, ...entries.map(([key]) => key.length + 1));

  return entries
    .map(([key, value]) => {
      const paddedKey = key.padEnd(keyWidth, ' ');

      if (value instanceof Variable) {
        return `${paddedKey}: ${prettyVar(value)}`;
      }

      if (value instanceof Constraint) {
        return `${paddedKey}: ${prettyConstraint(value, keyWidth + 2)}`;
      }

      return `${paddedKey}: ${prettyPenroseNum(value)}`;
    })
    .join('\n');
};

const prettyVar = (v: Variable) => {
  return `${VAR_PREFIX}${v.id}`;
};

const prettyConstraint = (c: Constraint, baseIndent = 0) => {
  return prettyPenroseNum(c.expr, 0, baseIndent);
};

const prettyNumber = (n: number) => {
  return Number.isInteger(n) ? `${n}` : n.toFixed(2);
};

type Prec = number;

const PREC = {
  atom: 100,
  call: 90,
  unary: 80,
  pow: 70,
  mul: 60,
  add: 50,
  comp: 40,
  logic: 30,
  ternary: 20
} as const;

const prettyPenroseNum = (expr: unknown, parentPrec: Prec = 0, indent = 0): string => {
  const rendered = renderPenroseNum(expr, indent);
  return parensIf(rendered.text, rendered.prec < parentPrec);
};

const renderPenroseNum = (expr: unknown, indent = 0): { text: string; prec: Prec } => {
  if (typeof expr === 'number') {
    return { text: prettyNumber(expr), prec: PREC.atom };
  }

  if (expr instanceof Variable) {
    return { text: prettyVar(expr), prec: PREC.atom };
  }

  if (!expr || typeof expr !== 'object') {
    return { text: JSON.stringify(expr), prec: PREC.atom };
  }

  const e = expr as { tag: string; [other: string]: unknown };

  if (e.tag === 'Var') {
    return { text: `${VAR_PREFIX}${String(e.id)}`, prec: PREC.atom };
  }

  if (e.tag === 'Unary') {
    const op = String(e.unop);

    if (isFunctionUnary(op)) {
      return prettyCall(op, [e.param], indent);
    }

    return {
      text: `${op}${prettyPenroseNum(e.param, PREC.unary, indent)}`,
      prec: PREC.unary
    };
  }

  if (e.tag === 'Binary') {
    return prettyBinary(String(e.binop), e.left, e.right, indent);
  }

  if (e.tag === 'Comp') {
    return prettyInfix(String(e.binop), e.left, e.right, PREC.comp, indent);
  }

  if (e.tag === 'Logic') {
    return prettyInfix(prettyLogicOp(String(e.binop)), e.left, e.right, PREC.logic, indent);
  }

  if (e.tag === 'Not') {
    return {
      text: `!${prettyPenroseNum(e.param, PREC.unary, indent)}`,
      prec: PREC.unary
    };
  }

  if (e.tag === 'Ternary') {
    const cond = prettyPenroseNum(e.cond, 0, indent);
    const thenExpr = prettyPenroseNum(e.then, 0, indent);
    const elseExpr = prettyPenroseNum(e.els, 0, indent);

    const inline = `${cond} ? ${thenExpr} : ${elseExpr}`;

    if (fitsInline(inline, indent)) {
      return { text: inline, prec: PREC.ternary };
    }

    return {
      text: [
        `${cond} ?`,
        `${spaces(indent + 1)}${thenExpr} :`,
        `${spaces(indent + 1)}${elseExpr}`
      ].join('\n'),
      prec: PREC.ternary
    };
  }

  if (e.tag === 'Nary') {
    throw new Error('Nary expressions are not supported in pretty printing');
  }

  return { text: JSON.stringify(expr), prec: PREC.atom };
};

const prettyBinary = (
  op: string,
  left: unknown,
  right: unknown,
  indent: number
): { text: string; prec: Prec } => {
  switch (op) {
    case '+':
    case '-':
      return prettyInfix(op, left, right, PREC.add, indent);

    case '*':
    case '/':
      return prettyInfix(op, left, right, PREC.mul, indent);

    case 'pow': {
      const l = prettyPenroseNum(left, PREC.pow, indent);
      const r = prettyPenroseNum(right, PREC.pow, indent);
      const inline = `${l} ^ ${r}`;

      return {
        text: inline,
        prec: PREC.pow
      };
    }

    case 'max':
    case 'min':
      return prettyCall(op, [left, right], indent);

    default:
      return prettyCall(op, [left, right], indent);
  }
};

const prettyInfix = (
  op: string,
  left: unknown,
  right: unknown,
  prec: Prec,
  indent: number
): { text: string; prec: Prec } => {
  const l = prettyPenroseNum(left, prec, indent);
  const r = prettyPenroseNum(right, prec + rightAssociativityBump(op), indent);

  const inline = `${l} ${op} ${r}`;

  if (fitsInline(inline, indent) && !inline.includes('\n')) {
    return { text: inline, prec };
  }

  return {
    text: [l, `${spaces(indent + 1)}${op} ${r}`].join('\n'),
    prec
  };
};

const prettyCall = (
  name: string,
  args: unknown[],
  indent: number
): { text: string; prec: Prec } => {
  const renderedArgs = args.map((arg) => prettyPenroseNum(arg, 0, indent + 1));
  const inline = `${name}(${renderedArgs.join(', ')})`;

  if (fitsInline(inline, indent) && !inline.includes('\n')) {
    return {
      text: inline,
      prec: PREC.call
    };
  }

  return {
    text: [
      `${name}(`,
      renderedArgs
        .map((arg, i) => {
          const comma = i === renderedArgs.length - 1 ? '' : ',';
          return `${spaces(indent + 1)}${arg}${comma}`;
        })
        .join('\n'),
      `${spaces(indent)})`
    ].join('\n'),
    prec: PREC.call
  };
};

const rightAssociativityBump = (op: string) => {
  return op === '-' || op === '/' ? 1 : 0;
};

const parensIf = (text: string, condition: boolean) => {
  return condition ? `(${text})` : text;
};

const spaces = (depth: number) => {
  return INDENT.repeat(depth);
};

const fitsInline = (text: string, indent: number) => {
  return text.length + spaces(indent).length <= MAX_INLINE_WIDTH;
};

const isFunctionUnary = (op: string) => {
  return ['abs', 'sqrt', 'log', 'log2', 'ln', 'sin', 'cos', 'tan', 'asin', 'acos', 'atan'].includes(
    op
  );
};

const prettyLogicOp = (op: string) => {
  switch (op) {
    case 'and':
    case '&&':
      return '&&';

    case 'or':
    case '||':
      return '||';

    default:
      return op;
  }
};
