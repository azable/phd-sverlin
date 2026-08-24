// THIS FILE IS GENERATED. Run: pnpm run generate:visualization-types

export type CodeHighlightLine = CodeToken[];

export interface CodeToken {
  tokenSourceRange: TextSourceRange;
  tokenText: string;
  tokenKind: CodeTokenKind;
}

export type CodeTokenKind =
  | 'codeNormal'
  | 'codeKeyword'
  | 'codeType'
  | 'codeNumber'
  | 'codeString'
  | 'codeComment'
  | 'codeFunction'
  | 'codeVariable'
  | 'codeOperator'
  | 'codeError';

export interface CoordinateSystem {
  systemName: string;
  systemUnitsPerInch: number;
  systemOrigin: string;
  systemYAxis: string;
}

export type CspValue = { kind: 'number'; value: number } | { kind: 'category'; value: string };

export interface CspVariable {
  id: CspVariableId;
  value: CspValue;
}

export type CspVariableId = string;

export type DecisionCoverage = 'exactEnumeration' | 'mipConditioning' | 'legacyCoverage';

export interface EdgeInsets {
  top: number;
  right: number;
  bottom: number;
  left: number;
}

export interface FindingEvidence {
  evidenceKey: string;
  evidenceValue: FindingValue;
  evidenceUnit?: string;
}

export type FindingSeverity = 'findingInfo' | 'findingWarning';

export type FindingValue =
  | { kind: 'findingNumber'; numberValue: number }
  | { kind: 'findingText'; textValue: string }
  | { kind: 'findingBoolean'; booleanValue: boolean };

export interface FontAxis {
  axisTag: string;
  axisValue: number;
}

export interface FontInstance {
  instanceFamily: string;
  instanceResourceId: ResourceId;
  instanceWeight: number;
  instanceStyle: string;
  instanceAxes: FontAxis[];
  instanceFeatures: string[];
}

export interface HslColor {
  hue: number;
  saturation: number;
  lightness: number;
}

export interface LayoutRect {
  rectX: number;
  rectY: number;
  rectWidth: number;
  rectHeight: number;
}

export type RenderInstanceId = number;

export interface ResourceDescriptor {
  descriptorId: ResourceId;
  descriptorKind: ResourceKind;
  descriptorSha256: Sha256;
  descriptorMediaType: string;
  descriptorByteLength: number;
}

export type ResourceId = string;

export type ResourceKind = 'fontResource' | 'textRunResource' | 'vectorResource';

export type SamplingMode = 'balancedChoices' | 'geometricMeasure' | 'legacyOptimizer';

export interface SamplingProvenance {
  mode: SamplingMode;
  coverage: DecisionCoverage;
}

export type Sha256 = string;

export interface StyleVariableBinding {
  field: string;
  variables: CspVariableId[];
}

export type TextDirection = 'textLeftToRight' | 'textRightToLeft';

export interface TextLayout {
  layoutSource: string;
  layoutWhitespace: TextWhitespace;
  layoutWrapMode: TextWrapMode;
  layoutFont: FontInstance;
  layoutFontSize: number;
  layoutPreferredSize: number;
  layoutLineHeight: number;
  layoutDirection: TextDirection;
  layoutScript: string;
  layoutLanguage: string;
  layoutAlignment: string;
  layoutContentBox: LayoutRect;
  layoutLines: TextLine[];
  layoutTextRunResource: ResourceId;
}

export interface TextLine {
  lineSourceRange: TextSourceRange;
  lineDisplayText: string;
  lineOriginX: number;
  lineBaselineY: number;
  lineAdvance: number;
  lineInkBounds: LayoutRect;
}

export interface TextSourceRange {
  sourceRangeStart: number;
  sourceRangeEnd: number;
}

export type TextWhitespace = 'textCollapseWhitespace' | 'textPreserveWhitespace';

export type TextWrapMode =
  | { kind: 'textNoAutomaticWrap' }
  | { kind: 'textPreferSingleLine'; wrapMaximumAutomaticBreaks: number };

export interface TimelineStep {
  label: string;
  instances: VisualInstance[];
}

export interface VisualBox {
  bounds: LayoutRect;
  padding: EdgeInsets;
  margin: EdgeInsets;
}

export type VisualContent =
  | { kind: 'plainTextContent'; textLayout: TextLayout }
  | {
      kind: 'codeTextContent';
      textLayout: TextLayout;
      textLanguage?: string;
      textHighlightLines: CodeHighlightLine[];
    }
  | { kind: 'legacyTextContent'; textSource: string };

export interface VisualElement {
  id: VisualId;
  role: string;
  box: VisualBox;
  children: VisualId[];
  content?: VisualContent;
  style: VisualStyle;
  styleVariables: StyleVariableBinding[];
}

export type VisualId = number;

export interface VisualInstance {
  id: RenderInstanceId;
  elementId: VisualId;
  originElementId?: VisualId;
  codeEmphasisRanges?: TextSourceRange[];
}

export interface VisualStyle {
  opacity?: number;
  zIndex?: number;
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

export interface Visualization {
  irVersion: number;
  seed: number;
  sourcePath: string;
  sampling?: SamplingProvenance;
  coordinates: CoordinateSystem;
  root: VisualId;
  resources: ResourceDescriptor[];
  findings: VisualizationFinding[];
  variables: CspVariable[];
  elements: VisualElement[];
  steps: TimelineStep[];
}

export interface VisualizationFinding {
  findingId: string;
  findingSeverity: FindingSeverity;
  findingCode: string;
  findingMessage: string;
  findingElementIds: VisualId[];
  findingStepIndices: number[];
  findingEvidence: FindingEvidence[];
}
