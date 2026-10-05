import { describe, expect, it } from 'vitest';
import { EditorState } from '@codemirror/state';

import { highlightRanges } from './selection-highlights';

const source = [
  '<Node items={values}>',
  '  <Node fill={index > i ? "a>b" : undefined} />',
  '  <Node',
  '    size="large">Title</Node>',
  '</Node>'
].join('\n');
const state = EditorState.create({ doc: source });
const text = (range: { from: number; to: number }) => source.slice(range.from, range.to);

describe('source highlights', () => {
  it('spans each whole <Node> tag, past > inside expressions and strings and across lines', () => {
    const ranges = highlightRanges(state, [
      { line: 2, column: 3 },
      { line: 1, column: 1 },
      { line: 3, column: 3 }
    ]);
    expect(ranges.map(text)).toEqual([
      '<Node items={values}>',
      '<Node fill={index > i ? "a>b" : undefined} />',
      '<Node\n    size="large">'
    ]);
  });

  it('skips positions that hold no <Node> tag and repeats of the same tag', () => {
    expect(
      highlightRanges(state, [
        { line: 2, column: 1 },
        { line: 9, column: 1 },
        { line: 1, column: 1 },
        { line: 1, column: 1 }
      ]).map(text)
    ).toEqual(['<Node items={values}>']);
  });
});
