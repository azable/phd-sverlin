/** Compatibility adapters for debugging-oriented project analysis exports. */

import {
  PostgresExportDataSource,
  prepareDataExport,
  verifyExportResource,
  writeDataDirectory,
  writeDataExport,
  type DataExportManifest,
  type ExportDataSource,
  type ExportSink,
  type ExportSnapshot,
  type PreparedDataExport
} from '$lib/server/data-export';
import { projectRepository, type ProjectReader } from '$lib/server/projects/repository';

export type AnalysisSnapshot = ExportSnapshot;
export type AnalysisExportSink = ExportSink;
export type AnalysisExportManifest = DataExportManifest;
export type PreparedAnalysisExport = PreparedDataExport;

export interface AnalysisDataSource {
  collect(projectId?: string): Promise<AnalysisSnapshot>;
  readResource(projectId: string, resourceId: string): Promise<Uint8Array>;
}

export class PostgresAnalysisDataSource implements AnalysisDataSource {
  private readonly source: PostgresExportDataSource;

  constructor(repository: ProjectReader = projectRepository) {
    this.source = new PostgresExportDataSource(repository);
  }

  collect(projectId?: string): Promise<AnalysisSnapshot> {
    return this.source.collect({ type: 'analysis', ...(projectId ? { projectId } : {}) });
  }

  readResource(projectId: string, resourceId: string): Promise<Uint8Array> {
    return this.source.readResource(projectId, resourceId);
  }
}

export function writeAnalysisExport(
  source: AnalysisDataSource,
  sink: AnalysisExportSink,
  options: { projectId?: string; exportedAt?: string } = {}
): Promise<AnalysisExportManifest> {
  return writeDataExport(
    analysisSource(source),
    sink,
    { type: 'analysis', ...(options.projectId ? { projectId: options.projectId } : {}) },
    options.exportedAt
  );
}

export function writeAnalysisDirectory(
  outputDirectory: string,
  projectId?: string,
  source: AnalysisDataSource = new PostgresAnalysisDataSource()
): Promise<AnalysisExportManifest> {
  return writeDataDirectory(
    outputDirectory,
    { type: 'analysis', ...(projectId ? { projectId } : {}) },
    analysisSource(source)
  );
}

export function prepareAnalysisExport(
  projectId?: string,
  source: AnalysisDataSource = new PostgresAnalysisDataSource()
): Promise<PreparedAnalysisExport> {
  return prepareDataExport(
    { type: 'analysis', ...(projectId ? { projectId } : {}) },
    projectId ? `analysis-project-${projectId}` : 'analysis-all-projects',
    analysisSource(source)
  );
}

export const verifyAnalysisResource = verifyExportResource;

function analysisSource(source: AnalysisDataSource): ExportDataSource {
  return {
    collect(scope) {
      if (scope.type !== 'analysis') throw new Error('Invalid analysis export scope.');
      return source.collect(scope.projectId);
    },
    readResource(projectId, resourceId) {
      return source.readResource(projectId, resourceId);
    }
  };
}
