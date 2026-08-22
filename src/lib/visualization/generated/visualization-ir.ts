// THIS FILE IS GENERATED. Run: pnpm run generate:visualization-types

export interface CanvasSpec {
  width: number;
  height: number;
}

export interface CompiledVisualization {
  seed: number;
  sourcePath: string;
  canvas: CanvasSpec;
  variables: CspVariable[];
  elements: VisualElement[];
  steps: TimelineStep[];
}

export type CspValue = { kind: 'number'; value: number } | { kind: 'category'; value: string };

export interface CspVariable {
  id: CspVariableId;
  value: CspValue;
}

export type CspVariableId = string;

export interface HslColor {
  hue: number;
  saturation: number;
  lightness: number;
}

export type RenderInstanceId = number;

export interface StyleVariableBinding {
  field: string;
  variables: CspVariableId[];
}

export interface TimelineStep {
  label: string;
  instances: VisualInstance[];
}

export interface VisualElement {
  id: VisualId;
  role: string;
  kind: VisualElementKind;
  content?: string;
  style: VisualStyle;
  styleVariables: StyleVariableBinding[];
}

export type VisualElementKind = { kind: 'trace' } | { kind: 'group'; children: VisualId[] };

export type VisualId = number;

export interface VisualInstance {
  id: RenderInstanceId;
  elementId: VisualId;
  originElementId?: VisualId;
}

export interface VisualStyle {
  top: number;
  left: number;
  width: number;
  height: number;
  opacity?: number;
  zIndex?: number;
  padding?: number;
  fontSize?: number;
  radius?: number;
  strokeWidth?: number;
  alpha?: number;
  fill?: HslColor;
  stroke?: HslColor;
  fontFamily?: string;
  fontWeight?: string;
  fontStyle?: string;
  textAlign?: string;
  borderStyle?: string;
  whiteSpace?: string;
}
