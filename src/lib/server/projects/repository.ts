/** PostgreSQL persistence for immutable project Timelines. */

import { and, asc, desc, eq, gt, isNull } from 'drizzle-orm';

import { summarizeProject } from '$lib/shared/projects/projection';
import type { NewProjectEvent, ProjectEvent } from '$lib/shared/projects/events';
import {
  normalizeProjectV2,
  type ProjectDocument,
  type ProjectId,
  type ProjectSummary
} from '$lib/shared/projects/model';
import { database } from '$lib/server/db';
import * as schema from '$lib/server/db/schema';

/** Validated document and stable events produced by one atomic append. */
export type ProjectAppendResult = {
  document: ProjectDocument;
  events: ProjectEvent[];
};

/** Read-only project access used by HTTP delivery and analysis code. */
export interface ProjectReader {
  list(ownerUserId?: string): Promise<ProjectSummary[]>;
  load(projectId: ProjectId): Promise<ProjectDocument>;
  eventsAfter(projectId: ProjectId, after: number): Promise<ProjectEvent[]>;
}

/** Project mutations used by command orchestration and administrative deletion. */
export interface ProjectWriter {
  initialize(): Promise<void>;
  create(document: ProjectDocument, ownerUserId?: string): Promise<ProjectDocument>;
  append(
    projectId: ProjectId,
    expectedHead: number,
    pendingEvents: NewProjectEvent[]
  ): Promise<ProjectAppendResult>;
  deleteAll(): Promise<void>;
}

/** Complete persistence contract; production has exactly one PostgreSQL implementation. */
export interface ProjectRepository extends ProjectReader, ProjectWriter {}

/** Raised when a requested active project does not exist. */
export class ProjectNotFoundError extends Error {
  constructor(projectId: string) {
    super(`Unknown project ${projectId}.`);
    this.name = 'ProjectNotFoundError';
  }
}

/** Raised when an append targets a project head that has already advanced. */
export class ProjectConflictError extends Error {
  constructor() {
    super('The project changed before this operation completed.');
    this.name = 'ProjectConflictError';
  }
}

/** PostgreSQL event repository used by the application service. */
export class PostgresProjectRepository implements ProjectRepository {
  async initialize(): Promise<void> {
    // Migrations own schema creation; application processes never mutate it implicitly.
  }

  async list(ownerUserId?: string): Promise<ProjectSummary[]> {
    const condition = ownerUserId
      ? and(eq(schema.projects.ownerUserId, ownerUserId), isNull(schema.projects.deletedAt))
      : isNull(schema.projects.deletedAt);
    const rows = await database()
      .select({
        projectId: schema.projects.id,
        title: schema.projects.title,
        updatedAt: schema.projects.updatedAt,
        eventCount: schema.projects.head,
        templateId: schema.projects.templateId,
        renderer: schema.projects.renderer
      })
      .from(schema.projects)
      .where(condition)
      .orderBy(desc(schema.projects.updatedAt));
    return rows.map((row) => ({ ...row, updatedAt: row.updatedAt.toISOString() }));
  }

  async create(document: ProjectDocument, ownerUserId?: string): Promise<ProjectDocument> {
    assertProjectId(document.projectId);
    const normalized = normalizeProjectV2(document);
    if (!ownerUserId) throw new Error('A project owner is required for PostgreSQL storage.');
    const summary = summarizeProject(normalized);
    await database().transaction(async (transaction) => {
      await transaction.insert(schema.projects).values({
        id: normalized.projectId,
        ownerUserId,
        head: summary.eventCount,
        title: summary.title,
        templateId: summary.templateId,
        renderer: summary.renderer ?? 'sverlin',
        createdAt: new Date(normalized.events[0].createdAt),
        updatedAt: new Date(summary.updatedAt)
      });
      await transaction.insert(schema.projectEvents).values(
        normalized.events.map((event) => ({
          projectId: normalized.projectId,
          eventId: event.id,
          operationId: event.operationId,
          event,
          createdAt: new Date(event.createdAt)
        }))
      );
    });
    return structuredClone(normalized);
  }

  async load(projectId: ProjectId): Promise<ProjectDocument> {
    assertProjectId(projectId);
    const project = await database()
      .select({ id: schema.projects.id })
      .from(schema.projects)
      .where(and(eq(schema.projects.id, projectId), isNull(schema.projects.deletedAt)))
      .limit(1);
    if (!project[0]) throw new ProjectNotFoundError(projectId);
    const rows = await database()
      .select({ event: schema.projectEvents.event })
      .from(schema.projectEvents)
      .where(eq(schema.projectEvents.projectId, projectId))
      .orderBy(asc(schema.projectEvents.eventId));
    return normalizeProjectV2({
      schemaVersion: 2,
      projectId,
      events: rows.map(({ event }) => event)
    });
  }

  async append(
    projectId: ProjectId,
    expectedHead: number,
    pendingEvents: NewProjectEvent[]
  ): Promise<ProjectAppendResult> {
    assertProjectId(projectId);

    return database().transaction(async (transaction) => {
      const locked = await transaction
        .select({ head: schema.projects.head })
        .from(schema.projects)
        .where(and(eq(schema.projects.id, projectId), isNull(schema.projects.deletedAt)))
        .for('update')
        .limit(1);
      if (!locked[0]) throw new ProjectNotFoundError(projectId);
      if (locked[0].head !== expectedHead) throw new ProjectConflictError();

      const events = pendingEvents.map(
        (pending, index): ProjectEvent =>
          ({ ...pending, id: expectedHead + index + 1 }) as ProjectEvent
      );
      const rows = await transaction
        .select({ event: schema.projectEvents.event })
        .from(schema.projectEvents)
        .where(eq(schema.projectEvents.projectId, projectId))
        .orderBy(asc(schema.projectEvents.eventId));
      const document = normalizeProjectV2({
        schemaVersion: 2,
        projectId,
        events: [...rows.map(({ event }) => event), ...events]
      });
      const summary = summarizeProject(document);

      if (events.length) {
        await transaction.insert(schema.projectEvents).values(
          events.map((event) => ({
            projectId,
            eventId: event.id,
            operationId: event.operationId,
            event,
            createdAt: new Date(event.createdAt)
          }))
        );
      }
      await transaction
        .update(schema.projects)
        .set({
          head: summary.eventCount,
          title: summary.title,
          templateId: summary.templateId,
          renderer: summary.renderer ?? 'sverlin',
          updatedAt: new Date(summary.updatedAt)
        })
        .where(eq(schema.projects.id, projectId));
      return { document: structuredClone(document), events: structuredClone(events) };
    });
  }

  async eventsAfter(projectId: ProjectId, after: number): Promise<ProjectEvent[]> {
    const project = await database()
      .select({ head: schema.projects.head })
      .from(schema.projects)
      .where(and(eq(schema.projects.id, projectId), isNull(schema.projects.deletedAt)))
      .limit(1);
    if (!project[0]) throw new ProjectNotFoundError(projectId);
    if (after > project[0].head) throw new ProjectConflictError();
    const rows = await database()
      .select({ event: schema.projectEvents.event })
      .from(schema.projectEvents)
      .where(
        and(eq(schema.projectEvents.projectId, projectId), gt(schema.projectEvents.eventId, after))
      )
      .orderBy(asc(schema.projectEvents.eventId));
    return rows.map(({ event }) => event);
  }

  async deleteAll(): Promise<void> {
    await database().delete(schema.projects);
  }
}

/** Default repository used by server routes and project operations. */
export const projectRepository: ProjectRepository = new PostgresProjectRepository();

function assertProjectId(projectId: string) {
  if (!isProjectId(projectId)) {
    throw new Error('Invalid project ID.');
  }
}

function isProjectId(projectId: string) {
  return /^[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}$/.test(projectId);
}
