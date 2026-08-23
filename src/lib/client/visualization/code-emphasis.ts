import type { CodeToken, CodeTokenKind, TextSourceRange } from '$lib/shared/visualization';

/** A renderer segment formed by intersecting static syntax and step emphasis. */
export type CodeRenderSegment = {
  sourceRange: TextSourceRange;
  text: string;
  tokenKind: CodeTokenKind;
  emphasized: boolean;
};

/**
 * Split static syntax tokens only where a step emphasis boundary crosses them.
 * Both input layers retain their own source ranges and neither changes text.
 */
export function codeRenderSegments(
  tokens: readonly CodeToken[],
  emphasisRanges: readonly TextSourceRange[]
): CodeRenderSegment[] {
  return tokens.flatMap((token) => splitToken(token, emphasisRanges));
}

function splitToken(
  token: CodeToken,
  emphasisRanges: readonly TextSourceRange[]
): CodeRenderSegment[] {
  const tokenStart = token.tokenSourceRange.sourceRangeStart;
  const tokenEnd = token.tokenSourceRange.sourceRangeEnd;
  if (tokenEnd === tokenStart) return [];

  const overlapping = emphasisRanges.filter(
    ({ sourceRangeStart, sourceRangeEnd }) =>
      sourceRangeEnd > tokenStart && sourceRangeStart < tokenEnd
  );
  const boundaries = new Set([tokenStart, tokenEnd]);
  for (const { sourceRangeStart, sourceRangeEnd } of overlapping) {
    boundaries.add(Math.max(tokenStart, sourceRangeStart));
    boundaries.add(Math.min(tokenEnd, sourceRangeEnd));
  }

  const ordered = [...boundaries].toSorted((left, right) => left - right);
  const tokenBytes = new TextEncoder().encode(token.tokenText);
  return ordered.slice(0, -1).map((start, index) => {
    const end = ordered[index + 1];
    return {
      sourceRange: { sourceRangeStart: start, sourceRangeEnd: end },
      text: decodeUtf8(tokenBytes, start - tokenStart, end - tokenStart),
      tokenKind: token.tokenKind,
      emphasized: overlapping.some(
        ({ sourceRangeStart, sourceRangeEnd }) => sourceRangeStart <= start && end <= sourceRangeEnd
      )
    };
  });
}

function decodeUtf8(bytes: Uint8Array, start: number, end: number): string {
  return new TextDecoder('utf-8', { fatal: true }).decode(bytes.slice(start, end));
}
