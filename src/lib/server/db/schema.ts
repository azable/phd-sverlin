/** PostgreSQL schema for Better Auth, project Timelines, and study data. */

import { relations, sql } from 'drizzle-orm';
import {
  bigint,
  boolean,
  check,
  doublePrecision,
  index,
  integer,
  jsonb,
  pgTable,
  primaryKey,
  text,
  timestamp,
  uniqueIndex,
  uuid,
  varchar
} from 'drizzle-orm/pg-core';

import type { ProjectSummary } from '$lib/shared/projects/model';
import type { ProjectEvent } from '$lib/shared/projects/events';
import type { VisualizationMode } from '$lib/shared/presentations';
import type { StudyRunKind } from '$lib/shared/study/projection';
import type {
  StudyInteractionCapturePolicy,
  StudyInteractionEventInput,
  StudyInteractionKind
} from '$lib/shared/study/interactions';

const timestamps = {
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull()
};

// Better Auth core and plugin tables. Property names intentionally match its
// Drizzle adapter model fields while SQL names remain conventional snake_case.
export const user = pgTable(
  'auth_user',
  {
    id: text('id').primaryKey(),
    name: text('name').notNull(),
    email: text('email').notNull().unique(),
    emailVerified: boolean('email_verified').default(false).notNull(),
    image: text('image'),
    username: text('username'),
    role: text('role').default('user'),
    banned: boolean('banned').default(false),
    banReason: text('ban_reason'),
    banExpires: timestamp('ban_expires', { withTimezone: true }),
    ...timestamps
  },
  (table) => [uniqueIndex('auth_user_username_unique').on(table.username)]
);

export const session = pgTable(
  'auth_session',
  {
    id: text('id').primaryKey(),
    expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
    token: text('token').notNull().unique(),
    ipAddress: text('ip_address'),
    userAgent: text('user_agent'),
    userId: text('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    impersonatedBy: text('impersonated_by'),
    ...timestamps
  },
  (table) => [index('auth_session_user_idx').on(table.userId)]
);

export const account = pgTable(
  'auth_account',
  {
    id: text('id').primaryKey(),
    issuer: text('issuer').notNull(),
    accountId: text('account_id').notNull(),
    providerId: text('provider_id').notNull(),
    userId: text('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    accessToken: text('access_token'),
    refreshToken: text('refresh_token'),
    idToken: text('id_token'),
    accessTokenExpiresAt: timestamp('access_token_expires_at', { withTimezone: true }),
    refreshTokenExpiresAt: timestamp('refresh_token_expires_at', { withTimezone: true }),
    scope: text('scope'),
    password: text('password'),
    ...timestamps
  },
  (table) => [
    index('auth_account_user_idx').on(table.userId),
    uniqueIndex('auth_account_issuer_unique').on(table.issuer, table.accountId)
  ]
);

export const verification = pgTable(
  'auth_verification',
  {
    id: text('id').primaryKey(),
    identifier: text('identifier').notNull(),
    value: text('value').notNull(),
    expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
    ...timestamps
  },
  (table) => [index('auth_verification_identifier_idx').on(table.identifier)]
);

export const passkey = pgTable(
  'auth_passkey',
  {
    id: text('id').primaryKey(),
    name: text('name'),
    publicKey: text('public_key').notNull(),
    userId: text('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    credentialID: text('credential_id').notNull().unique(),
    counter: integer('counter').notNull(),
    deviceType: text('device_type').notNull(),
    backedUp: boolean('backed_up').notNull(),
    transports: text('transports'),
    aaguid: text('aaguid'),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow()
  },
  (table) => [index('auth_passkey_user_idx').on(table.userId)]
);

export const rateLimit = pgTable('auth_rate_limit', {
  id: text('id').primaryKey(),
  key: text('key').notNull().unique(),
  count: integer('count').notNull(),
  lastRequest: bigint('last_request', { mode: 'number' }).notNull()
});

export const projects = pgTable(
  'project',
  {
    id: varchar('id', { length: 128 }).primaryKey(),
    ownerUserId: text('owner_user_id')
      .notNull()
      .references(() => user.id),
    head: integer('head').notNull(),
    title: text('title').notNull(),
    templateId: text('template_id').notNull(),
    mode: text('mode').$type<VisualizationMode>().default('sverlin').notNull(),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
    deletedAt: timestamp('deleted_at', { withTimezone: true })
  },
  (table) => [
    index('project_owner_updated_idx').on(table.ownerUserId, table.updatedAt),
    index('project_updated_idx').on(table.updatedAt)
  ]
);

/** One durable execution of an exact study protocol, for a participant or an administrator preview. */
export const studyRuns = pgTable(
  'study_run',
  {
    id: uuid('id').defaultRandom().primaryKey(),
    kind: text('kind').$type<StudyRunKind>().notNull(),
    ownerUserId: text('owner_user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    studyId: text('study_id').notNull(),
    studyVersion: integer('study_version').notNull(),
    armId: text('arm_id').notNull(),
    currentPhaseIndex: integer('current_phase_index').default(0).notNull(),
    startPhaseIndex: integer('start_phase_index').default(0).notNull(),
    stopAfterPhaseIndex: integer('stop_after_phase_index'),
    startedAt: timestamp('started_at', { withTimezone: true }),
    completedAt: timestamp('completed_at', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull()
  },
  (table) => [
    check('study_run_kind_check', sql`${table.kind} in ('participant', 'preview')`),
    check('study_run_current_phase_check', sql`${table.currentPhaseIndex} >= 0`),
    check('study_run_start_phase_check', sql`${table.startPhaseIndex} >= 0`),
    check(
      'study_run_stop_phase_check',
      sql`${table.stopAfterPhaseIndex} is null or ${table.stopAfterPhaseIndex} >= ${table.startPhaseIndex}`
    ),
    index('study_run_protocol_arm_idx').on(
      table.kind,
      table.studyId,
      table.studyVersion,
      table.armId
    ),
    index('study_run_owner_created_idx').on(table.ownerUserId, table.createdAt)
  ]
);

/** Counterbalanced study assignment retained independently from authentication state. */
export const studyEnrollments = pgTable(
  'study_enrollment',
  {
    userId: text('user_id')
      .primaryKey()
      .references(() => user.id, { onDelete: 'cascade' }),
    runId: uuid('run_id')
      .notNull()
      .unique()
      .references(() => studyRuns.id, { onDelete: 'cascade' }),
    giftCardUrl: text('gift_card_url'),
    enrolledAt: timestamp('enrolled_at', { withTimezone: true }).defaultNow().notNull()
  },
  (table) => [index('study_enrollment_run_idx').on(table.runId)]
);

/** Durable execution record for each phase in one participant's resolved sequence. */
export const studyPhaseRuns = pgTable(
  'study_phase_run',
  {
    runId: uuid('run_id')
      .notNull()
      .references(() => studyRuns.id, { onDelete: 'cascade' }),
    phaseId: text('phase_id').notNull(),
    sequenceIndex: integer('sequence_index').notNull(),
    kind: text('kind').notNull(),
    conditionId: text('condition_id'),
    mode: text('mode').$type<VisualizationMode>(),
    layout: text('layout'),
    view: text('view'),
    projectId: varchar('project_id', { length: 128 }).references(() => projects.id, {
      onDelete: 'set null'
    }),
    status: text('status').$type<'active' | 'completed'>().default('active').notNull(),
    startedAt: timestamp('started_at', { withTimezone: true }),
    deadlineAt: timestamp('deadline_at', { withTimezone: true }),
    endedAt: timestamp('ended_at', { withTimezone: true }),
    endReason: text('end_reason').$type<
      'continued' | 'deadline' | 'participant-early' | 'admin-forced' | 'flow-complete'
    >()
  },
  (table) => [
    primaryKey({ columns: [table.runId, table.phaseId] }),
    uniqueIndex('study_phase_run_sequence_unique').on(table.runId, table.sequenceIndex),
    uniqueIndex('study_phase_run_project_unique').on(table.projectId)
  ]
);

/** One best-effort browser observation stream for an active participant task. */
export const projectInteractionSessions = pgTable(
  'project_interaction_session',
  {
    id: uuid('id').primaryKey(),
    projectId: varchar('project_id', { length: 128 })
      .notNull()
      .references(() => projects.id, { onDelete: 'cascade' }),
    schemaVersion: integer('schema_version').notNull(),
    clientStartedAt: timestamp('client_started_at', { withTimezone: true }).notNull(),
    clientTimeOrigin: doublePrecision('client_time_origin').notNull(),
    initialViewport: jsonb('initial_viewport')
      .$type<{ width: number; height: number; devicePixelRatio: number }>()
      .notNull(),
    applicationVersion: text('application_version').notNull(),
    buildSha: text('build_sha'),
    capture: jsonb('capture').$type<StudyInteractionCapturePolicy>().notNull(),
    acceptedThrough: integer('accepted_through').default(0).notNull(),
    clientStoppedAt: timestamp('client_stopped_at', { withTimezone: true }),
    recordedThrough: integer('recorded_through'),
    deliveryCompletedAt: timestamp('delivery_completed_at', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull()
  },
  (table) => [
    check('project_interaction_session_schema_check', sql`${table.schemaVersion} = 1`),
    check('project_interaction_session_sequence_check', sql`${table.acceptedThrough} >= 0`),
    check(
      'project_interaction_session_terminal_pair_check',
      sql`(${table.clientStoppedAt} is null) = (${table.recordedThrough} is null)`
    ),
    check(
      'project_interaction_session_recorded_sequence_check',
      sql`${table.recordedThrough} is null or (${table.recordedThrough} >= 0 and ${table.acceptedThrough} <= ${table.recordedThrough})`
    ),
    check(
      'project_interaction_session_completion_check',
      sql`${table.deliveryCompletedAt} is null or (${table.recordedThrough} is not null and ${table.acceptedThrough} = ${table.recordedThrough})`
    ),
    index('project_interaction_session_project_idx').on(table.projectId)
  ]
);

/** Ordered state, activation, pointer, draft, and lifecycle observation. */
export const projectInteractionEvents = pgTable(
  'project_interaction_event',
  {
    sessionId: uuid('session_id')
      .notNull()
      .references(() => projectInteractionSessions.id, { onDelete: 'cascade' }),
    sequence: integer('sequence').notNull(),
    kind: text('kind').$type<StudyInteractionKind>().notNull(),
    elapsedMs: integer('elapsed_ms').notNull(),
    clientOccurredAt: timestamp('client_occurred_at', { withTimezone: true }).notNull(),
    projectHead: integer('project_head').notNull(),
    payload: jsonb('payload').$type<StudyInteractionEventInput['payload']>().notNull(),
    receivedAt: timestamp('received_at', { withTimezone: true }).defaultNow().notNull()
  },
  (table) => [
    primaryKey({ columns: [table.sessionId, table.sequence] }),
    check('project_interaction_event_sequence_check', sql`${table.sequence} > 0`),
    check('project_interaction_event_elapsed_check', sql`${table.elapsedMs} >= 0`),
    check('project_interaction_event_head_check', sql`${table.projectHead} >= 0`),
    index('project_interaction_event_received_idx').on(table.receivedAt)
  ]
);

export const projectEvents = pgTable(
  'project_event',
  {
    projectId: varchar('project_id', { length: 128 })
      .notNull()
      .references(() => projects.id, { onDelete: 'cascade' }),
    eventId: integer('event_id').notNull(),
    operationId: uuid('operation_id').notNull(),
    event: jsonb('event').$type<ProjectEvent>().notNull(),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull()
  },
  (table) => [
    primaryKey({ columns: [table.projectId, table.eventId] }),
    index('project_event_operation_idx').on(table.projectId, table.operationId)
  ]
);

// Better Auth enables joined session queries, so its Drizzle adapter needs
// both sides of each user-owned authentication relation in the schema object.
export const userRelations = relations(user, ({ many }) => ({
  sessions: many(session),
  accounts: many(account),
  passkeys: many(passkey)
}));

export const sessionRelations = relations(session, ({ one }) => ({
  user: one(user, {
    fields: [session.userId],
    references: [user.id]
  })
}));

export const accountRelations = relations(account, ({ one }) => ({
  user: one(user, {
    fields: [account.userId],
    references: [user.id]
  })
}));

export const passkeyRelations = relations(passkey, ({ one }) => ({
  user: one(user, {
    fields: [passkey.userId],
    references: [user.id]
  })
}));

export type ProjectRow = typeof projects.$inferSelect;
export type ProjectSummaryRow = ProjectSummary;
