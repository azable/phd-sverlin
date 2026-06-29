export type CssValue = string | number | boolean;

export type RenderStyle = Record<string, CssValue>;

export type RenderElement = {
  blockId: number;
  nodeKey: string;
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
  outputPath?: string;
  timeoutMs?: number;
  timedOut?: boolean;
  durationMs: number;
  exitCode: number | null;
  stdout: string;
  stderr: string;
  compiledJson?: string;
  error?: string;
};

export type CompileLockHolder = {
  owner: string;
  pid: number;
  startedAt: string;
  cwd: string;
  command: string;
  args: string[];
  seed?: number;
  details?: boolean;
  outputPath?: string;
  lockPath: string;
};

export type CompileStatus =
  | {
      running: false;
    }
  | ({ running: true } & CompileLockHolder);

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
  lock?: CompileLockHolder;
};

export type CompileStreamStatus = {
  ok: true;
  status: 'starting' | 'running' | 'complete';
  seed: number;
  details: boolean;
  debug?: CompileDebug;
};

export type CompileStreamOutput = {
  ok: true;
  chunk: string;
};

export type CompileStreamSuccess = VisualizationSuccess;

export type CompileStreamFailure = VisualizationFailure & {
  status: number;
};
