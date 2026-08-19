// THIS FILE IS GENERATED. Run: pnpm run generate:visualization-types

export interface CanvasSpec {
  width: number;
  height: number;
  background?: HslColor;
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

export interface InstanceOrigin {
  instanceId: RenderInstanceId;
  elementId: VisualId;
}

export type RenderInstanceId = string;

export interface SourceMetadata {
  path: string;
  compilerVersion: string;
}

export interface StyleVariableTrace {
  top: CspVariableId[];
  left: CspVariableId[];
  width: CspVariableId[];
  height: CspVariableId[];
  opacity: CspVariableId[];
  zIndex: CspVariableId[];
  padding: CspVariableId[];
  fontSize: CspVariableId[];
  radius: CspVariableId[];
  strokeWidth: CspVariableId[];
  alpha: CspVariableId[];
  fill: CspVariableId[];
  stroke: CspVariableId[];
  fontFamily: CspVariableId[];
  fontWeight: CspVariableId[];
  fontStyle: CspVariableId[];
  textAlign: CspVariableId[];
  borderStyle: CspVariableId[];
  whiteSpace: CspVariableId[];
}

export interface VisualElement {
  id: VisualId;
  nodeId: number;
  nodeKey: string;
  role: string;
  kind: VisualElementKind;
  content?: string;
  style: VisualStyle;
  variables: StyleVariableTrace;
}

export type VisualElementKind = { kind: 'trace' } | { kind: 'group'; children: VisualId[] };

export type VisualId = string;

export interface VisualInstance {
  id: RenderInstanceId;
  elementId: VisualId;
  origin?: InstanceOrigin;
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

export interface VisualizationFrame {
  durationMs: number;
  instances: VisualInstance[];
}

export interface VisualizationPackage {
  schemaVersion: number;
  seed: number;
  source: SourceMetadata;
  canvas: CanvasSpec;
  variables: CspVariable[];
  elements: VisualElement[];
  frames: VisualizationFrame[];
}
