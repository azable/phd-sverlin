CREATE TABLE "project_interaction_event" (
	"session_id" uuid NOT NULL,
	"sequence" integer NOT NULL,
	"kind" text NOT NULL,
	"elapsed_ms" integer NOT NULL,
	"client_occurred_at" timestamp with time zone NOT NULL,
	"project_head" integer NOT NULL,
	"payload" jsonb NOT NULL,
	"received_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "project_interaction_event_session_id_sequence_pk" PRIMARY KEY("session_id","sequence"),
	CONSTRAINT "project_interaction_event_sequence_check" CHECK ("project_interaction_event"."sequence" > 0),
	CONSTRAINT "project_interaction_event_elapsed_check" CHECK ("project_interaction_event"."elapsed_ms" >= 0),
	CONSTRAINT "project_interaction_event_head_check" CHECK ("project_interaction_event"."project_head" >= 0)
);
--> statement-breakpoint
CREATE TABLE "project_interaction_session" (
	"id" uuid PRIMARY KEY NOT NULL,
	"project_id" varchar(128) NOT NULL,
	"schema_version" integer NOT NULL,
	"client_started_at" timestamp with time zone NOT NULL,
	"client_time_origin" double precision NOT NULL,
	"initial_viewport" jsonb NOT NULL,
	"application_version" text NOT NULL,
	"build_sha" text,
	"capture" jsonb NOT NULL,
	"accepted_through" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "project_interaction_session_schema_check" CHECK ("project_interaction_session"."schema_version" = 1),
	CONSTRAINT "project_interaction_session_sequence_check" CHECK ("project_interaction_session"."accepted_through" >= 0)
);
--> statement-breakpoint
ALTER TABLE "project_interaction_event" ADD CONSTRAINT "project_interaction_event_session_id_project_interaction_session_id_fk" FOREIGN KEY ("session_id") REFERENCES "public"."project_interaction_session"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "project_interaction_session" ADD CONSTRAINT "project_interaction_session_project_id_project_id_fk" FOREIGN KEY ("project_id") REFERENCES "public"."project"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "project_interaction_event_received_idx" ON "project_interaction_event" USING btree ("received_at");--> statement-breakpoint
CREATE INDEX "project_interaction_session_project_idx" ON "project_interaction_session" USING btree ("project_id");