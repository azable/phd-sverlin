/**
 * Environment-neutral visualization wire contract generated from the Haskell IR.
 *
 * @packageDocumentation
 */

export type * from './generated/visualization-ir';

import * as v from 'valibot';

import type { Visualization } from './generated/visualization-ir';
import { validateVisualizationReferences, visualizationV2Schema } from './schema';

const finite = v.pipe(v.number(), v.finite());
const natural = v.pipe(finite, v.safeInteger(), v.minValue(0));
const legacyColor = v.strictObject({ hue: finite, saturation: finite, lightness: finite });
const legacyStyle = v.strictObject({
  top: finite,
  left: finite,
  width: finite,
  height: finite,
  opacity: v.optional(finite),
  zIndex: v.optional(finite),
  padding: v.optional(finite),
  fontSize: v.optional(finite),
  radius: v.optional(finite),
  strokeWidth: v.optional(finite),
  alpha: v.optional(finite),
  fill: v.optional(legacyColor),
  stroke: v.optional(legacyColor),
  fontFamily: v.optional(v.string()),
  fontWeight: v.optional(v.string()),
  fontStyle: v.optional(v.string()),
  textAlign: v.optional(v.string()),
  borderStyle: v.optional(v.string()),
  whiteSpace: v.optional(v.string())
});
const legacyElement = v.strictObject({
  id: natural,
  role: v.string(),
  kind: v.variant('kind', [
    v.strictObject({ kind: v.picklist(['leaf', 'trace']) }),
    v.strictObject({ kind: v.literal('group'), children: v.array(natural) })
  ]),
  content: v.optional(v.string()),
  style: legacyStyle,
  styleVariables: v.array(v.strictObject({ field: v.string(), variables: v.array(v.string()) }))
});
const legacyVisualizationSchema = v.strictObject({
  seed: finite,
  sourcePath: v.string(),
  sampling: v.optional(
    v.strictObject({
      mode: v.picklist(['balancedChoices', 'geometricMeasure', 'legacyOptimizer']),
      coverage: v.picklist(['exactEnumeration', 'mipConditioning', 'legacyCoverage'])
    })
  ),
  canvas: v.strictObject({ width: finite, height: finite }),
  variables: v.array(
    v.strictObject({
      id: v.string(),
      value: v.variant('kind', [
        v.strictObject({ kind: v.literal('number'), value: finite }),
        v.strictObject({ kind: v.literal('category'), value: v.string() })
      ])
    })
  ),
  elements: v.array(legacyElement),
  steps: v.array(
    v.strictObject({
      label: v.string(),
      instances: v.array(
        v.strictObject({
          id: natural,
          elementId: natural,
          originElementId: v.optional(natural)
        })
      )
    })
  )
});

/** Raised when compiler output does not satisfy a supported visualization contract. */
export class InvalidVisualizationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'InvalidVisualizationError';
  }
}

/** Decode and strictly validate Haskell-generated visualization output at its boundary. */
export function decodeVisualization(json: string): Visualization {
  let input: unknown;
  try {
    input = JSON.parse(json);
  } catch (error) {
    throw new InvalidVisualizationError(
      `Invalid visualization JSON: ${error instanceof Error ? error.message : String(error)}`
    );
  }

  if (isRecord(input) && input.irVersion !== undefined && input.irVersion !== 2) {
    throw new InvalidVisualizationError(
      `Unsupported visualization IR version ${String(input.irVersion)}.`
    );
  }

  const parsed = v.safeParse(visualizationV2Schema, input);
  const visualization = parsed.success
    ? parsed.output
    : migrateLegacy(input, v.summarize(parsed.issues));

  try {
    validateVisualizationReferences(visualization);
  } catch (error) {
    throw new InvalidVisualizationError(error instanceof Error ? error.message : String(error));
  }
  return visualization;
}

function migrateLegacy(input: unknown, v2Issues: string): Visualization {
  const legacy = v.safeParse(legacyVisualizationSchema, input);
  if (!legacy.success) {
    throw new InvalidVisualizationError(`Invalid visualization IR v2: ${v2Issues}`);
  }

  const migrated: Visualization = {
    irVersion: 2,
    seed: legacy.output.seed,
    sourcePath: legacy.output.sourcePath,
    ...(legacy.output.sampling ? { sampling: legacy.output.sampling } : {}),
    coordinates: {
      systemName: 'sverlin-css96-y-down',
      systemUnitsPerInch: 96,
      systemOrigin: 'top-left',
      systemYAxis: 'down'
    },
    canvas: legacy.output.canvas,
    resources: [],
    findings: [],
    variables: legacy.output.variables,
    elements: legacy.output.elements.map(({ content, kind, ...element }) => ({
      ...element,
      kind: kind.kind === 'group' ? kind : { kind: 'leaf' as const },
      ...(content === undefined
        ? {}
        : { content: { kind: 'legacyTextContent' as const, textSource: content } })
    })),
    steps: legacy.output.steps
  };
  const validated = v.safeParse(visualizationV2Schema, migrated);
  if (!validated.success) {
    throw new InvalidVisualizationError(
      `Invalid migrated visualization IR: ${v.summarize(validated.issues)}`
    );
  }
  return validated.output;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
