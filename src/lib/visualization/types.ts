export type CssValue = string | number | boolean;

export type RenderStyle = Record<string, CssValue>;

export type RenderElement = {
  blockId: number;
  nodeKey: string;
  pieceKey: string;
  kind: string;
  content: string;
  style: RenderStyle;
};

export type RenderId = string;

export type RenderOrigin = {
  id: RenderId;
  element: RenderElement;
};

export type RenderPatch =
  | {
      kind: 'create';
      id: RenderId;
      element: RenderElement;
      origin?: RenderOrigin;
    }
  | {
      kind: 'update';
      id: RenderId;
      from: RenderElement;
      to: RenderElement;
    }
  | {
      kind: 'destroy';
      id: RenderId;
      element: RenderElement;
    };

export type CompiledTrace = {
  seed?: number;
  canvas: {
    width: number;
    height: number;
  };
  frames: RenderPatch[][];
};

export type LiveElement = RenderElement & {
  id: RenderId;
  exiting?: boolean;
};

export type CompileDebug = {
  command: string;
  args: string[];
  cwd: string;
  durationMs: number;
  exitCode: number | null;
  stdout: string;
  stderr: string;
  error?: string;
};

export type VisualizationSuccess = {
  ok: true;
  trace: CompiledTrace;
  seed: number;
  details: boolean;
  debug: CompileDebug;
};

export type VisualizationFailure = {
  ok: false;
  error: string;
  seed?: number;
  details?: boolean;
  debug?: CompileDebug;
};

export type VisualizationResponse = VisualizationSuccess | VisualizationFailure;
