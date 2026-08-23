/** Runtime validation for the versioned compiler visualization boundary. */

import * as v from 'valibot';

import type { Visualization } from './generated/visualization-ir';

const finite = v.pipe(v.number(), v.finite());
const integer = v.pipe(finite, v.safeInteger());
const natural = v.pipe(integer, v.minValue(0));
const positive = v.pipe(
  finite,
  v.minValue(0, 'Expected a positive number.'),
  v.check((n) => n > 0)
);
const text = v.pipe(v.string(), v.nonEmpty());
const sha256 = v.pipe(v.string(), v.regex(/^[a-f0-9]{64}$/));
const resourceId = v.pipe(v.string(), v.regex(/^sha256-[a-f0-9]{64}$/));

const hslColorSchema = v.strictObject({
  hue: finite,
  saturation: v.pipe(finite, v.minValue(0), v.maxValue(1)),
  lightness: v.pipe(finite, v.minValue(0), v.maxValue(1))
});

const layoutRectSchema = v.strictObject({
  rectX: finite,
  rectY: finite,
  rectWidth: v.pipe(finite, v.minValue(0)),
  rectHeight: v.pipe(finite, v.minValue(0))
});

const fontAxisSchema = v.strictObject({
  axisTag: v.pipe(v.string(), v.regex(/^[\x20-\x7e]{4}$/)),
  axisValue: finite
});

const fontInstanceSchema = v.strictObject({
  instanceFamily: text,
  instanceResourceId: resourceId,
  instanceWeight: v.pipe(finite, v.safeInteger(), v.minValue(1), v.maxValue(1000)),
  instanceStyle: v.picklist(['normal', 'italic']),
  instanceAxes: v.array(fontAxisSchema),
  instanceFeatures: v.array(v.pipe(text, v.regex(/^[\x20-\x7e]{4}(?:=-?\d+(?:\.\d+)?)?$/)))
});

const textSourceRangeSchema = v.strictObject({
  sourceRangeStart: natural,
  sourceRangeEnd: natural
});

const textLineSchema = v.strictObject({
  lineSourceRange: textSourceRangeSchema,
  lineDisplayText: v.string(),
  lineOriginX: finite,
  lineBaselineY: finite,
  lineAdvance: v.pipe(finite, v.minValue(0)),
  lineInkBounds: layoutRectSchema
});

const textLayoutSchema = v.strictObject({
  layoutSource: v.string(),
  layoutWhitespace: v.picklist(['textCollapseWhitespace', 'textPreserveWhitespace']),
  layoutWrapMode: v.variant('kind', [
    v.strictObject({ kind: v.literal('textNoAutomaticWrap') }),
    v.strictObject({
      kind: v.literal('textPreferSingleLine'),
      wrapMaximumAutomaticBreaks: natural
    })
  ]),
  layoutFont: fontInstanceSchema,
  layoutFontSize: positive,
  layoutPreferredSize: positive,
  layoutLineHeight: positive,
  layoutDirection: v.picklist(['textLeftToRight', 'textRightToLeft']),
  layoutScript: text,
  layoutLanguage: text,
  layoutAlignment: v.picklist(['left', 'center', 'right']),
  layoutContentBox: layoutRectSchema,
  layoutLines: v.pipe(v.array(textLineSchema), v.minLength(1)),
  layoutTextRunResource: resourceId
});

const codeTokenSchema = v.strictObject({
  tokenSourceRange: textSourceRangeSchema,
  tokenText: v.string(),
  tokenKind: v.picklist([
    'codeNormal',
    'codeKeyword',
    'codeType',
    'codeNumber',
    'codeString',
    'codeComment',
    'codeFunction',
    'codeVariable',
    'codeOperator',
    'codeError'
  ])
});

const codeHighlightLineSchema = v.array(codeTokenSchema);

const visualContentSchema = v.variant('kind', [
  v.strictObject({ kind: v.literal('plainTextContent'), textLayout: textLayoutSchema }),
  v.strictObject({
    kind: v.literal('codeTextContent'),
    textLayout: textLayoutSchema,
    textLanguage: v.optional(text),
    textHighlightLines: v.array(codeHighlightLineSchema)
  }),
  v.strictObject({ kind: v.literal('legacyTextContent'), textSource: v.string() })
]);

const visualStyleSchema = v.strictObject({
  top: finite,
  left: finite,
  width: v.pipe(finite, v.minValue(0)),
  height: v.pipe(finite, v.minValue(0)),
  opacity: v.optional(v.pipe(finite, v.minValue(0), v.maxValue(1))),
  zIndex: v.optional(finite),
  padding: v.optional(v.pipe(finite, v.minValue(0))),
  fontSize: v.optional(positive),
  radius: v.optional(v.pipe(finite, v.minValue(0))),
  strokeWidth: v.optional(v.pipe(finite, v.minValue(0))),
  alpha: v.optional(v.pipe(finite, v.minValue(0), v.maxValue(1))),
  fill: v.optional(hslColorSchema),
  stroke: v.optional(hslColorSchema),
  fontFamily: v.optional(v.string()),
  fontWeight: v.optional(v.string()),
  fontStyle: v.optional(v.string()),
  textAlign: v.optional(v.string()),
  borderStyle: v.optional(v.string()),
  whiteSpace: v.optional(v.string())
});

const styleVariableBindingSchema = v.strictObject({
  field: text,
  variables: v.array(v.string())
});

const visualElementSchema = v.strictObject({
  id: natural,
  role: v.string(),
  kind: v.variant('kind', [
    v.strictObject({ kind: v.literal('leaf') }),
    v.strictObject({ kind: v.literal('group'), children: v.array(natural) })
  ]),
  content: v.optional(visualContentSchema),
  style: visualStyleSchema,
  styleVariables: v.array(styleVariableBindingSchema)
});

const resourceDescriptorSchema = v.strictObject({
  descriptorId: resourceId,
  descriptorKind: v.picklist(['fontResource', 'textRunResource', 'vectorResource']),
  descriptorSha256: sha256,
  descriptorMediaType: text,
  descriptorByteLength: natural
});

const findingValueSchema = v.variant('kind', [
  v.strictObject({ kind: v.literal('findingNumber'), numberValue: finite }),
  v.strictObject({ kind: v.literal('findingText'), textValue: v.string() }),
  v.strictObject({ kind: v.literal('findingBoolean'), booleanValue: v.boolean() })
]);

const findingEvidenceSchema = v.strictObject({
  evidenceKey: text,
  evidenceValue: findingValueSchema,
  evidenceUnit: v.optional(v.string())
});

const findingSchema = v.strictObject({
  findingId: text,
  findingSeverity: v.picklist(['findingInfo', 'findingWarning']),
  findingCode: text,
  findingMessage: text,
  findingElementIds: v.array(natural),
  findingStepIndices: v.array(natural),
  findingEvidence: v.array(findingEvidenceSchema)
});

const cspVariableSchema = v.strictObject({
  id: v.string(),
  value: v.variant('kind', [
    v.strictObject({ kind: v.literal('number'), value: finite }),
    v.strictObject({ kind: v.literal('category'), value: v.string() })
  ])
});

const visualInstanceSchema = v.strictObject({
  id: natural,
  elementId: natural,
  originElementId: v.optional(natural),
  codeEmphasisRanges: v.optional(v.array(textSourceRangeSchema))
});

const timelineStepSchema = v.strictObject({
  label: v.string(),
  instances: v.array(visualInstanceSchema)
});

/** Strict runtime schema for visualization IR version 2. */
export const visualizationV2Schema = v.strictObject({
  irVersion: v.literal(2),
  seed: integer,
  sourcePath: v.string(),
  sampling: v.optional(
    v.strictObject({
      mode: v.picklist(['balancedChoices', 'geometricMeasure', 'legacyOptimizer']),
      coverage: v.picklist(['exactEnumeration', 'mipConditioning', 'legacyCoverage'])
    })
  ),
  coordinates: v.strictObject({
    systemName: v.literal('sverlin-css96-y-down'),
    systemUnitsPerInch: v.literal(96),
    systemOrigin: v.literal('top-left'),
    systemYAxis: v.literal('down')
  }),
  canvas: v.strictObject({ width: positive, height: positive }),
  resources: v.array(resourceDescriptorSchema),
  findings: v.array(findingSchema),
  variables: v.array(cspVariableSchema),
  elements: v.array(visualElementSchema),
  steps: v.array(timelineStepSchema)
});

/** Validate cross-resource and cross-element invariants not expressible structurally. */
export function validateVisualizationReferences(visualization: Visualization): void {
  assertUnique(
    visualization.resources.map(({ descriptorId }) => descriptorId),
    'resource ID'
  );
  assertUnique(
    visualization.elements.map(({ id }) => id),
    'visual element ID'
  );
  assertUnique(
    visualization.variables.map(({ id }) => id),
    'CSP variable ID'
  );
  assertUnique(
    visualization.findings.map(({ findingId }) => findingId),
    'visualization finding ID'
  );

  const resources = new Map(
    visualization.resources.map((resource) => [resource.descriptorId, resource])
  );
  const elementRegistry = new Map(visualization.elements.map((element) => [element.id, element]));
  const elements = new Set(elementRegistry.keys());

  for (const resource of visualization.resources) {
    if (resource.descriptorId !== `sha256-${resource.descriptorSha256}`) {
      throw new Error(`Resource ${resource.descriptorId} does not match its SHA-256 digest.`);
    }
  }

  for (const element of visualization.elements) {
    if (element.kind.kind === 'group') {
      for (const child of element.kind.children) {
        if (!elements.has(child))
          throw new Error(`Element ${element.id} references unknown child ${child}.`);
      }
    }

    if (
      element.content?.kind !== 'plainTextContent' &&
      element.content?.kind !== 'codeTextContent'
    ) {
      continue;
    }
    const layout = element.content.textLayout;
    const font = resources.get(layout.layoutFont.instanceResourceId);
    const run = resources.get(layout.layoutTextRunResource);
    if (font?.descriptorKind !== 'fontResource') {
      throw new Error(`Element ${element.id} references an unknown font resource.`);
    }
    if (run?.descriptorKind !== 'textRunResource') {
      throw new Error(`Element ${element.id} references an unknown text-run resource.`);
    }

    let previousEnd = 0;
    const sourceBytes = new TextEncoder().encode(layout.layoutSource);
    const sourceByteLength = sourceBytes.byteLength;
    for (const line of layout.layoutLines) {
      const { sourceRangeStart: start, sourceRangeEnd: end } = line.lineSourceRange;
      if (start < previousEnd || end < start || end > sourceByteLength) {
        throw new Error(`Element ${element.id} has an invalid or unordered text source range.`);
      }
      previousEnd = end;
    }

    if (element.content.kind === 'codeTextContent') {
      if (element.content.textHighlightLines.length !== layout.layoutLines.length) {
        throw new Error(`Element ${element.id} has misaligned code highlight lines.`);
      }
      element.content.textHighlightLines.forEach((highlightLine, lineIndex) => {
        const layoutLine = layout.layoutLines[lineIndex];
        const lineStart = layoutLine.lineSourceRange.sourceRangeStart;
        const lineEnd = layoutLine.lineSourceRange.sourceRangeEnd;
        if (decodeUtf8Range(sourceBytes, lineStart, lineEnd) !== layoutLine.lineDisplayText) {
          throw new Error(
            `Element ${element.id} has code text that differs from its source range.`
          );
        }
        if (
          highlightLine.map(({ tokenText }) => tokenText).join('') !== layoutLine.lineDisplayText
        ) {
          throw new Error(`Element ${element.id} has code tokens that alter verbatim text.`);
        }
        let tokenEnd = lineStart;
        for (const token of highlightLine) {
          const { sourceRangeStart: start, sourceRangeEnd: end } = token.tokenSourceRange;
          if (
            start !== tokenEnd ||
            end < start ||
            end > lineEnd ||
            new TextEncoder().encode(token.tokenText).byteLength !== end - start
          ) {
            throw new Error(`Element ${element.id} has invalid code token ranges.`);
          }
          tokenEnd = end;
        }
        if (tokenEnd !== lineEnd) {
          throw new Error(`Element ${element.id} has incomplete code token ranges.`);
        }
      });
    }
  }

  visualization.steps.forEach((step, stepIndex) => {
    assertUnique(
      step.instances.map(({ id }) => id),
      `render instance ID in step ${stepIndex}`
    );
    for (const instance of step.instances) {
      if (!elements.has(instance.elementId)) {
        throw new Error(`Step ${stepIndex} references unknown element ${instance.elementId}.`);
      }
      if (instance.originElementId !== undefined && !elements.has(instance.originElementId)) {
        throw new Error(`Step ${stepIndex} references unknown origin ${instance.originElementId}.`);
      }
      if (instance.codeEmphasisRanges !== undefined) {
        const content = elementRegistry.get(instance.elementId)?.content;
        if (content?.kind !== 'codeTextContent') {
          throw new Error(`Step ${stepIndex} emphasizes non-code element ${instance.elementId}.`);
        }
        validateCodeEmphasisRanges(
          instance.codeEmphasisRanges,
          content.textLayout.layoutSource,
          stepIndex,
          instance.elementId
        );
      }
    }
  });

  for (const finding of visualization.findings) {
    for (const elementId of finding.findingElementIds) {
      if (!elements.has(elementId))
        throw new Error(`Finding ${finding.findingId} references unknown element.`);
    }
    for (const stepIndex of finding.findingStepIndices) {
      if (stepIndex >= visualization.steps.length) {
        throw new Error(`Finding ${finding.findingId} references unknown step ${stepIndex}.`);
      }
    }
  }
}

function validateCodeEmphasisRanges(
  ranges: readonly { sourceRangeStart: number; sourceRangeEnd: number }[],
  source: string,
  stepIndex: number,
  elementId: number
): void {
  const sourceBytes = new TextEncoder().encode(source);
  let previousEnd = 0;
  for (const { sourceRangeStart: start, sourceRangeEnd: end } of ranges) {
    if (start < previousEnd || end <= start || end > sourceBytes.byteLength) {
      throw new Error(
        `Step ${stepIndex} has invalid code emphasis ranges for element ${elementId}.`
      );
    }
    decodeUtf8Range(sourceBytes, start, end);
    previousEnd = end;
  }
}

function assertUnique(values: readonly (string | number)[], label: string): void {
  if (new Set(values).size !== values.length) throw new Error(`Duplicate ${label}.`);
}

function decodeUtf8Range(source: Uint8Array, start: number, end: number): string {
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(source.slice(start, end));
  } catch {
    throw new Error('Text source range does not end at a valid UTF-8 boundary.');
  }
}
