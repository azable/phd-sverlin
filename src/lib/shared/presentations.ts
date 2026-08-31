/** Renderer-neutral presentation, layout, and HTML-frame contracts. */

import * as v from 'valibot';

import {
  compilationProvenanceSchema,
  compilationResourceSchema,
  positiveSchema,
  recordedTextSchema,
  targetDiagnosticSchema,
  textSchema
} from './projects/events/values';

/** Stable renderer modes available to projects and study conditions. */
export const visualizationModeSchema = v.picklist(['sverlin', 'html']);

/** Number of simultaneously displayed presentations. */
export const presentationLayoutSchema = v.picklist(['single', 'comparison']);

/** Server-authorized projection used to build a workspace response. */
export const workspaceViewSchema = v.picklist(['participant', 'developer']);

/** One complete static HTML checkpoint. */
export const htmlFrameSchema = v.strictObject({
  label: textSchema,
  html: textSchema
});

/** Editable source contract for a steppable, script-free HTML presentation. */
export const htmlFramesManifestSchema = v.strictObject({
  format: v.literal('sverlin-html-frames'),
  version: v.literal(1),
  frames: v.pipe(v.array(htmlFrameSchema), v.minLength(1))
});

/** Stable identity for a presentation, independent of its Timeline event position. */
export const presentationIdSchema = v.pipe(v.string(), v.uuid());

const presentationEnvelope = { presentationId: presentationIdSchema };

/** Compiler-produced presentation recorded without exposing its implementation language. */
export const sverlinPresentationSchema = v.strictObject({
  ...presentationEnvelope,
  format: v.literal('sverlin-ir-v1'),
  stepSignature: textSchema,
  seed: positiveSchema,
  source: recordedTextSchema,
  render: recordedTextSchema,
  resources: v.optional(v.array(compilationResourceSchema)),
  provenance: v.optional(compilationProvenanceSchema),
  targetDiagnostics: v.optional(v.array(targetDiagnosticSchema))
});

/** Scenario-aware compiler presentation; views with one scenario key may align. */
export const sverlinPresentationV2Schema = v.strictObject({
  ...presentationEnvelope,
  format: v.literal('sverlin-ir-v2'),
  scenarioKey: v.pipe(v.string(), v.regex(/^[a-f0-9]{64}$/)),
  scenarioSeed: positiveSchema,
  viewSeed: positiveSchema,
  source: recordedTextSchema,
  render: recordedTextSchema,
  resources: v.optional(v.array(compilationResourceSchema)),
  provenance: v.optional(compilationProvenanceSchema),
  targetDiagnostics: v.optional(v.array(targetDiagnosticSchema))
});

/** AI- or user-authored static HTML checkpoints plus the exact safe render bundle. */
export const htmlFramesPresentationSchema = v.strictObject({
  ...presentationEnvelope,
  format: v.literal('html-frames-v1'),
  stepSignature: textSchema,
  authored: recordedTextSchema,
  rendered: recordedTextSchema,
  generationEventId: v.optional(positiveSchema)
});

/** Any steppable presentation accepted by the workspace. */
export const renderablePresentationSchema = v.variant('format', [
  sverlinPresentationSchema,
  sverlinPresentationV2Schema,
  htmlFramesPresentationSchema
]);

export type VisualizationMode = v.InferOutput<typeof visualizationModeSchema>;
export type PresentationLayout = v.InferOutput<typeof presentationLayoutSchema>;
export type WorkspaceView = v.InferOutput<typeof workspaceViewSchema>;
export type HtmlFrame = v.InferOutput<typeof htmlFrameSchema>;
export type HtmlFramesManifest = v.InferOutput<typeof htmlFramesManifestSchema>;
export type SverlinPresentation = v.InferOutput<typeof sverlinPresentationSchema>;
export type SverlinPresentationV2 = v.InferOutput<typeof sverlinPresentationV2Schema>;
export type CompilerPresentation = SverlinPresentation | SverlinPresentationV2;
export type HtmlFramesPresentation = v.InferOutput<typeof htmlFramesPresentationSchema>;
export type RenderablePresentation = v.InferOutput<typeof renderablePresentationSchema>;

/** Return the labels used by the renderer-neutral playback controls. */
export function presentationStepLabels(presentation: RenderablePresentation): string[] {
  if (presentation.format === 'html-frames-v1') {
    const parsed = v.parse(htmlFramesManifestSchema, JSON.parse(presentation.rendered.text));
    return parsed.frames.map(({ label }) => label);
  }
  const value = JSON.parse(presentation.render.text) as { steps?: Array<{ label?: unknown }> };
  const labels = value.steps?.map(({ label }) => (typeof label === 'string' ? label : '')) ?? [];
  return labels.length ? labels : ['Initial view'];
}

/** Whether a presentation contains compiler-produced Sverlin IR. */
export function isSverlinPresentation(
  presentation: RenderablePresentation
): presentation is CompilerPresentation {
  return presentation.format === 'sverlin-ir-v1' || presentation.format === 'sverlin-ir-v2';
}

/** Compatibility identity for synchronized playback. */
export function presentationScenarioKey(presentation: CompilerPresentation): string {
  return presentation.format === 'sverlin-ir-v2'
    ? presentation.scenarioKey
    : `legacy:${presentation.source.sha256}:${presentation.stepSignature}`;
}

/** Seed controlling this presentation's visual choices. */
export function presentationViewSeed(presentation: CompilerPresentation): number {
  return presentation.format === 'sverlin-ir-v2' ? presentation.viewSeed : presentation.seed;
}

/** Wrap a validated static fragment in the single iframe isolation policy used by every client. */
export function staticHtmlFrameDocument(html: string): string {
  const policy = [
    "default-src 'none'",
    "style-src 'unsafe-inline'",
    'img-src data:',
    'font-src data:',
    "script-src 'none'",
    "connect-src 'none'",
    "media-src 'none'",
    "object-src 'none'",
    "frame-src 'none'",
    "base-uri 'none'",
    "form-action 'none'"
  ].join('; ');
  return `<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="${policy}"><style>html,body{width:100%;height:100%;margin:0;overflow:hidden;font-family:system-ui,sans-serif}*,*::before,*::after{box-sizing:border-box}</style></head><body>${html}</body></html>`;
}
