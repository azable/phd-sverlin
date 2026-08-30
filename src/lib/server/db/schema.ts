/** PostgreSQL schema for Better Auth, projects, events, and resource metadata. */

import { relations } from 'drizzle-orm';
import {
  bigint,
  boolean,
  customType,
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

import type { ProjectEvent } from '$lib/shared/projects/events';
import type { ProjectSummary } from '$lib/shared/projects/model';

const timestamps = {
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull()
};

const bytea = customType<{ data: Uint8Array; driverData: Uint8Array }>({
  dataType: () => 'bytea'
});

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
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
    deletedAt: timestamp('deleted_at', { withTimezone: true })
  },
  (table) => [
    index('project_owner_updated_idx').on(table.ownerUserId, table.updatedAt),
    index('project_updated_idx').on(table.updatedAt)
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

export const projectResources = pgTable(
  'project_resource',
  {
    projectId: varchar('project_id', { length: 128 })
      .notNull()
      .references(() => projects.id, { onDelete: 'cascade' }),
    resourceId: varchar('resource_id', { length: 80 }).notNull(),
    bytes: bytea('bytes').notNull(),
    sha256: varchar('sha256', { length: 64 }).notNull(),
    byteLength: integer('byte_length').notNull(),
    mediaType: text('media_type').notNull(),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull()
  },
  (table) => [primaryKey({ columns: [table.projectId, table.resourceId] })]
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
