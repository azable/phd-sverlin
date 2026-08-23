import { describe, expect, it } from 'vitest';

import type { CodeToken } from '$lib/shared/visualization';
import { codeRenderSegments } from './code-emphasis';

describe('codeRenderSegments', () => {
  it('intersects UTF-8 emphasis ranges with syntax tokens without changing either role', () => {
    const tokens: CodeToken[] = [
      {
        tokenSourceRange: { sourceRangeStart: 0, sourceRangeEnd: 2 },
        tokenText: 'λ',
        tokenKind: 'codeVariable'
      },
      {
        tokenSourceRange: { sourceRangeStart: 2, sourceRangeEnd: 5 },
        tokenText: ' = ',
        tokenKind: 'codeOperator'
      },
      {
        tokenSourceRange: { sourceRangeStart: 5, sourceRangeEnd: 6 },
        tokenText: '1',
        tokenKind: 'codeNumber'
      }
    ];

    const segments = codeRenderSegments(tokens, [{ sourceRangeStart: 0, sourceRangeEnd: 4 }]);

    expect(segments).toEqual([
      {
        sourceRange: { sourceRangeStart: 0, sourceRangeEnd: 2 },
        text: 'λ',
        tokenKind: 'codeVariable',
        emphasized: true
      },
      {
        sourceRange: { sourceRangeStart: 2, sourceRangeEnd: 4 },
        text: ' =',
        tokenKind: 'codeOperator',
        emphasized: true
      },
      {
        sourceRange: { sourceRangeStart: 4, sourceRangeEnd: 5 },
        text: ' ',
        tokenKind: 'codeOperator',
        emphasized: false
      },
      {
        sourceRange: { sourceRangeStart: 5, sourceRangeEnd: 6 },
        text: '1',
        tokenKind: 'codeNumber',
        emphasized: false
      }
    ]);
    expect(segments.map(({ text }) => text).join('')).toBe('λ = 1');
  });

  it('retains static token boundaries when a step has no emphasis', () => {
    const token: CodeToken = {
      tokenSourceRange: { sourceRangeStart: 0, sourceRangeEnd: 3 },
      tokenText: 'let',
      tokenKind: 'codeKeyword'
    };

    expect(codeRenderSegments([token], [])).toEqual([
      {
        sourceRange: token.tokenSourceRange,
        text: 'let',
        tokenKind: 'codeKeyword',
        emphasized: false
      }
    ]);
  });
});
