import { describe, expect, it } from 'vitest';

import { decodeVisualization, InvalidVisualizationError, type Visualization } from './index';

describe('decodeVisualization', () => {
  it('strictly accepts a well-formed version-three visualization', () => {
    expect(decodeVisualization(JSON.stringify(visualization()))).toEqual(visualization());
  });

  it('rejects unknown version-three fields instead of silently stripping them', () => {
    expect(() =>
      decodeVisualization(JSON.stringify({ ...visualization(), unexpected: true }))
    ).toThrow(InvalidVisualizationError);
  });

  it('rejects unsupported versions and dangling resource references', () => {
    expect(() => decodeVisualization(JSON.stringify({ ...visualization(), irVersion: 2 }))).toThrow(
      InvalidVisualizationError
    );

    const malformed = visualization();
    malformed.elements[0].content = {
      kind: 'plainTextContent',
      textLayout: {
        layoutSource: 'hello',
        layoutWhitespace: 'textCollapseWhitespace',
        layoutWrapMode: { kind: 'textNoAutomaticWrap' },
        layoutFont: {
          instanceFamily: 'Inter',
          instanceResourceId: `sha256-${'1'.repeat(64)}`,
          instanceWeight: 400,
          instanceStyle: 'normal',
          instanceAxes: [{ axisTag: 'wght', axisValue: 400 }],
          instanceFeatures: []
        },
        layoutFontSize: 14,
        layoutPreferredSize: 14,
        layoutLineHeight: 17,
        layoutDirection: 'textLeftToRight',
        layoutScript: 'Latn',
        layoutLanguage: 'und',
        layoutAlignment: 'center',
        layoutContentBox: { rectX: 0, rectY: 0, rectWidth: 100, rectHeight: 20 },
        layoutLines: [
          {
            lineSourceRange: { sourceRangeStart: 0, sourceRangeEnd: 5 },
            lineDisplayText: 'hello',
            lineOriginX: 0,
            lineBaselineY: 14,
            lineAdvance: 30,
            lineInkBounds: { rectX: 0, rectY: 2, rectWidth: 30, rectHeight: 14 }
          }
        ],
        layoutTextRunResource: `sha256-${'2'.repeat(64)}`
      }
    };

    expect(() => decodeVisualization(JSON.stringify(malformed))).toThrow(
      'references an unknown font resource'
    );
  });

  it('rejects the unversioned historical wire shape', () => {
    const current = visualization();
    const legacy = {
      seed: current.seed,
      sourcePath: current.sourcePath,
      canvas: current.canvas,
      variables: current.variables,
      elements: current.elements.map((element) => ({
        id: element.id,
        role: element.role,
        style: { top: 0, left: 0, width: 100, height: 20 },
        styleVariables: element.styleVariables,
        kind: { kind: 'trace' },
        content: 'historical'
      })),
      steps: current.steps
    };

    expect(() => decodeVisualization(JSON.stringify(legacy))).toThrow(InvalidVisualizationError);
  });

  it('requires an acyclic single-parent element hierarchy', () => {
    const cyclic = visualization();
    cyclic.elements.push({
      id: -1,
      role: 'Node.parent',
      box: emptyBox(),
      children: [0],
      style: {},
      styleVariables: []
    });
    cyclic.elements[0].children = [-1];
    expect(() => decodeVisualization(JSON.stringify(cyclic))).toThrow(
      'Element hierarchy contains a cycle'
    );

    const multipleParents = visualization();
    multipleParents.elements.push(
      {
        id: -1,
        role: 'Node.first',
        box: emptyBox(),
        children: [0],
        style: {},
        styleVariables: []
      },
      {
        id: -2,
        role: 'Node.second',
        box: emptyBox(),
        children: [0],
        style: {},
        styleVariables: []
      }
    );
    expect(() => decodeVisualization(JSON.stringify(multipleParents))).toThrow(
      'Element 0 has multiple parents'
    );
  });

  it('keeps render-instance IDs nonnegative even when element IDs are signed', () => {
    const current = visualization();
    current.elements[0].id = -1;
    current.steps[0].instances[0].elementId = -1;
    expect(decodeVisualization(JSON.stringify(current)).elements[0].id).toBe(-1);

    current.steps[0].instances[0].id = -1;
    expect(() => decodeVisualization(JSON.stringify(current))).toThrow(InvalidVisualizationError);
  });

  it('accepts code highlight arrays and enforces exact UTF-8 token ranges', () => {
    const current = visualization();
    const fontSha = '1'.repeat(64);
    const runSha = '2'.repeat(64);
    current.resources = [
      {
        descriptorId: `sha256-${fontSha}`,
        descriptorKind: 'fontResource',
        descriptorSha256: fontSha,
        descriptorMediaType: 'font/ttf',
        descriptorByteLength: 10
      },
      {
        descriptorId: `sha256-${runSha}`,
        descriptorKind: 'textRunResource',
        descriptorSha256: runSha,
        descriptorMediaType: 'application/vnd.sverlin.text-run-v2',
        descriptorByteLength: 20
      }
    ];
    current.elements[0].content = {
      kind: 'codeTextContent',
      textLayout: {
        layoutSource: 'λ = 1',
        layoutWhitespace: 'textPreserveWhitespace',
        layoutWrapMode: { kind: 'textNoAutomaticWrap' },
        layoutFont: {
          instanceFamily: 'JetBrains Mono NL',
          instanceResourceId: `sha256-${fontSha}`,
          instanceWeight: 400,
          instanceStyle: 'normal',
          instanceAxes: [{ axisTag: 'wght', axisValue: 400 }],
          instanceFeatures: ['liga=0', 'calt=0']
        },
        layoutFontSize: 14,
        layoutPreferredSize: 14,
        layoutLineHeight: 17,
        layoutDirection: 'textLeftToRight',
        layoutScript: 'Grek',
        layoutLanguage: 'und',
        layoutAlignment: 'left',
        layoutContentBox: { rectX: 0, rectY: 0, rectWidth: 100, rectHeight: 20 },
        layoutLines: [
          {
            lineSourceRange: { sourceRangeStart: 0, sourceRangeEnd: 6 },
            lineDisplayText: 'λ = 1',
            lineOriginX: 0,
            lineBaselineY: 14,
            lineAdvance: 36,
            lineInkBounds: { rectX: 0, rectY: 2, rectWidth: 36, rectHeight: 14 }
          }
        ],
        layoutTextRunResource: `sha256-${runSha}`
      },
      textLanguage: 'haskell',
      textHighlightLines: [
        [
          {
            tokenSourceRange: { sourceRangeStart: 0, sourceRangeEnd: 6 },
            tokenText: 'λ = 1',
            tokenKind: 'codeNormal'
          }
        ]
      ]
    };

    expect(decodeVisualization(JSON.stringify(current)).elements[0].content).toMatchObject({
      kind: 'codeTextContent',
      textHighlightLines: [[{ tokenText: 'λ = 1' }]]
    });

    current.steps[0].instances[0].codeEmphasisRanges = [{ sourceRangeStart: 0, sourceRangeEnd: 2 }];
    expect(decodeVisualization(JSON.stringify(current)).steps[0].instances[0]).toMatchObject({
      codeEmphasisRanges: [{ sourceRangeStart: 0, sourceRangeEnd: 2 }]
    });

    current.steps[0].instances[0].codeEmphasisRanges[0].sourceRangeEnd = 1;
    expect(() => decodeVisualization(JSON.stringify(current))).toThrow(
      'Text source range does not end at a valid UTF-8 boundary'
    );
    current.steps[0].instances[0].codeEmphasisRanges[0].sourceRangeEnd = 2;

    if (current.elements[0].content.kind !== 'codeTextContent') throw new Error('unreachable');
    current.elements[0].content.textHighlightLines[0][0].tokenSourceRange.sourceRangeEnd = 5;
    expect(() => decodeVisualization(JSON.stringify(current))).toThrow('invalid code token ranges');
  });
});

function visualization(): Visualization {
  return {
    irVersion: 3,
    seed: 1,
    sourcePath: 'Main.sverlin',
    sampling: { mode: 'balancedChoices', coverage: 'exactEnumeration' },
    coordinates: {
      systemName: 'sverlin-css96-y-down',
      systemUnitsPerInch: 96,
      systemOrigin: 'top-left',
      systemYAxis: 'down'
    },
    canvas: { width: 100, height: 80 },
    resources: [],
    findings: [],
    variables: [],
    elements: [
      {
        id: 0,
        role: 'Value',
        box: {
          bounds: { rectX: 0, rectY: 0, rectWidth: 100, rectHeight: 20 },
          padding: { top: 0, right: 0, bottom: 0, left: 0 },
          margin: { top: 0, right: 0, bottom: 0, left: 0 }
        },
        children: [],
        content: { kind: 'legacyTextContent', textSource: 'hello' },
        style: {},
        styleVariables: []
      }
    ],
    steps: [{ label: 'show', instances: [{ id: 0, elementId: 0 }] }]
  };
}

function emptyBox() {
  return {
    bounds: { rectX: 0, rectY: 0, rectWidth: 100, rectHeight: 20 },
    padding: { top: 0, right: 0, bottom: 0, left: 0 },
    margin: { top: 0, right: 0, bottom: 0, left: 0 }
  };
}
