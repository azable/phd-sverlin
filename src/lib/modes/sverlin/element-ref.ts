/**
 * Where a selected element came from: the <Node> tag its id names in the presentation's source
 * (see provideNodeIds in library/type-context.ts for how ids are formed).
 */

export type ElementLocation = {
  /** Line and column (both from 1) of the element's <Node> tag. */
  line: number;
  column: number;
  /** Which render of that tag it was, from 1, such as the third time round a loop. */
  occurrence: number;
  /** Item indices within collections that drew the element themselves, outermost first. */
  items: number[];
  /** The source line holding the tag, trimmed and shortened. */
  markup: string;
};

const elementId = /^(\d{1,5}):(\d{1,5})(?:#(\d{1,5}))?((?:\/\d{1,5}){0,8})$/u;
const maxMarkup = 200;

/** Locate an element id in a Sverlin source, or undefined if it names no <Node> tag there. */
export function locateElement(source: string, id: string): ElementLocation | undefined {
  const match = elementId.exec(id);
  if (!match) return undefined;
  const line = Number(match[1]);
  const column = Number(match[2]);
  const text = source.split('\n')[line - 1];
  if (text === undefined || !/^<Node(?:[\s/>]|$)/u.test(text.slice(column - 1))) return undefined;
  const trimmed = text.trim();
  return {
    line,
    column,
    occurrence: match[3] ? Number(match[3]) : 1,
    items: match[4] ? match[4].slice(1).split('/').map(Number) : [],
    markup: trimmed.length > maxMarkup ? `${trimmed.slice(0, maxMarkup - 1)}…` : trimmed
  };
}
