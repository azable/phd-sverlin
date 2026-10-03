CREATE TABLE "auth_account" (
	"id" text PRIMARY KEY NOT NULL,
	"issuer" text NOT NULL,
	"account_id" text NOT NULL,
	"provider_id" text NOT NULL,
	"user_id" text NOT NULL,
	"access_token" text,
	"refresh_token" text,
	"id_token" text,
	"access_token_expires_at" timestamp with time zone,
	"refresh_token_expires_at" timestamp with time zone,
	"scope" text,
	"password" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "auth_passkey" (
	"id" text PRIMARY KEY NOT NULL,
	"name" text,
	"public_key" text NOT NULL,
	"user_id" text NOT NULL,
	"credential_id" text NOT NULL,
	"counter" integer NOT NULL,
	"device_type" text NOT NULL,
	"backed_up" boolean NOT NULL,
	"transports" text,
	"aaguid" text,
	"created_at" timestamp with time zone DEFAULT now(),
	CONSTRAINT "auth_passkey_credential_id_unique" UNIQUE("credential_id")
);
--> statement-breakpoint
CREATE TABLE "project_event" (
	"project_id" varchar(128) NOT NULL,
	"event_id" integer NOT NULL,
	"operation_id" uuid NOT NULL,
	"event" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "project_event_project_id_event_id_pk" PRIMARY KEY("project_id","event_id")
);
--> statement-breakpoint
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
	"client_stopped_at" timestamp with time zone,
	"recorded_through" integer,
	"delivery_completed_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "project_interaction_session_schema_check" CHECK ("project_interaction_session"."schema_version" = 1),
	CONSTRAINT "project_interaction_session_sequence_check" CHECK ("project_interaction_session"."accepted_through" >= 0),
	CONSTRAINT "project_interaction_session_terminal_pair_check" CHECK (("project_interaction_session"."client_stopped_at" is null) = ("project_interaction_session"."recorded_through" is null)),
	CONSTRAINT "project_interaction_session_recorded_sequence_check" CHECK ("project_interaction_session"."recorded_through" is null or ("project_interaction_session"."recorded_through" >= 0 and "project_interaction_session"."accepted_through" <= "project_interaction_session"."recorded_through")),
	CONSTRAINT "project_interaction_session_completion_check" CHECK ("project_interaction_session"."delivery_completed_at" is null or ("project_interaction_session"."recorded_through" is not null and "project_interaction_session"."accepted_through" = "project_interaction_session"."recorded_through"))
);
--> statement-breakpoint
CREATE TABLE "project" (
	"id" varchar(128) PRIMARY KEY NOT NULL,
	"owner_user_id" text NOT NULL,
	"head" integer NOT NULL,
	"title" text NOT NULL,
	"template_id" text NOT NULL,
	"renderer" text DEFAULT 'sverlin' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "auth_rate_limit" (
	"id" text PRIMARY KEY NOT NULL,
	"key" text NOT NULL,
	"count" integer NOT NULL,
	"last_request" bigint NOT NULL,
	CONSTRAINT "auth_rate_limit_key_unique" UNIQUE("key")
);
--> statement-breakpoint
CREATE TABLE "auth_session" (
	"id" text PRIMARY KEY NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"token" text NOT NULL,
	"ip_address" text,
	"user_agent" text,
	"user_id" text NOT NULL,
	"impersonated_by" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "auth_session_token_unique" UNIQUE("token")
);
--> statement-breakpoint
CREATE TABLE "study_enrollment" (
	"user_id" text PRIMARY KEY NOT NULL,
	"run_id" uuid NOT NULL,
	"gift_card_url" text,
	"enrolled_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "study_enrollment_run_id_unique" UNIQUE("run_id")
);
--> statement-breakpoint
CREATE TABLE "study_phase_run" (
	"run_id" uuid NOT NULL,
	"phase_id" text NOT NULL,
	"sequence_index" integer NOT NULL,
	"kind" text NOT NULL,
	"condition_id" text,
	"renderer" text,
	"layout" text,
	"view" text,
	"project_id" varchar(128),
	"status" text DEFAULT 'active' NOT NULL,
	"started_at" timestamp with time zone,
	"deadline_at" timestamp with time zone,
	"ended_at" timestamp with time zone,
	"end_reason" text,
	CONSTRAINT "study_phase_run_run_id_phase_id_pk" PRIMARY KEY("run_id","phase_id")
);
--> statement-breakpoint
CREATE TABLE "study_run" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"mode" text NOT NULL,
	"owner_user_id" text NOT NULL,
	"study_id" text NOT NULL,
	"study_version" integer NOT NULL,
	"arm_id" text NOT NULL,
	"current_phase_index" integer DEFAULT 0 NOT NULL,
	"start_phase_index" integer DEFAULT 0 NOT NULL,
	"stop_after_phase_index" integer,
	"started_at" timestamp with time zone,
	"completed_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "study_run_mode_check" CHECK ("study_run"."mode" in ('participant', 'preview')),
	CONSTRAINT "study_run_current_phase_check" CHECK ("study_run"."current_phase_index" >= 0),
	CONSTRAINT "study_run_start_phase_check" CHECK ("study_run"."start_phase_index" >= 0),
	CONSTRAINT "study_run_stop_phase_check" CHECK ("study_run"."stop_after_phase_index" is null or "study_run"."stop_after_phase_index" >= "study_run"."start_phase_index")
);
--> statement-breakpoint
CREATE TABLE "auth_user" (
	"id" text PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"email" text NOT NULL,
	"email_verified" boolean DEFAULT false NOT NULL,
	"image" text,
	"username" text,
	"role" text DEFAULT 'user',
	"banned" boolean DEFAULT false,
	"ban_reason" text,
	"ban_expires" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "auth_user_email_unique" UNIQUE("email")
);
--> statement-breakpoint
CREATE TABLE "auth_verification" (
	"id" text PRIMARY KEY NOT NULL,
	"identifier" text NOT NULL,
	"value" text NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "auth_account" ADD CONSTRAINT "auth_account_user_id_auth_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."auth_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "auth_passkey" ADD CONSTRAINT "auth_passkey_user_id_auth_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."auth_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "project_event" ADD CONSTRAINT "project_event_project_id_project_id_fk" FOREIGN KEY ("project_id") REFERENCES "public"."project"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "project_interaction_event" ADD CONSTRAINT "project_interaction_event_session_id_project_interaction_session_id_fk" FOREIGN KEY ("session_id") REFERENCES "public"."project_interaction_session"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "project_interaction_session" ADD CONSTRAINT "project_interaction_session_project_id_project_id_fk" FOREIGN KEY ("project_id") REFERENCES "public"."project"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "project" ADD CONSTRAINT "project_owner_user_id_auth_user_id_fk" FOREIGN KEY ("owner_user_id") REFERENCES "public"."auth_user"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "auth_session" ADD CONSTRAINT "auth_session_user_id_auth_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."auth_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "study_enrollment" ADD CONSTRAINT "study_enrollment_user_id_auth_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."auth_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "study_enrollment" ADD CONSTRAINT "study_enrollment_run_id_study_run_id_fk" FOREIGN KEY ("run_id") REFERENCES "public"."study_run"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "study_phase_run" ADD CONSTRAINT "study_phase_run_run_id_study_run_id_fk" FOREIGN KEY ("run_id") REFERENCES "public"."study_run"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "study_phase_run" ADD CONSTRAINT "study_phase_run_project_id_project_id_fk" FOREIGN KEY ("project_id") REFERENCES "public"."project"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "study_run" ADD CONSTRAINT "study_run_owner_user_id_auth_user_id_fk" FOREIGN KEY ("owner_user_id") REFERENCES "public"."auth_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "auth_account_user_idx" ON "auth_account" USING btree ("user_id");--> statement-breakpoint
CREATE UNIQUE INDEX "auth_account_issuer_unique" ON "auth_account" USING btree ("issuer","account_id");--> statement-breakpoint
CREATE INDEX "auth_passkey_user_idx" ON "auth_passkey" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "project_event_operation_idx" ON "project_event" USING btree ("project_id","operation_id");--> statement-breakpoint
CREATE INDEX "project_interaction_event_received_idx" ON "project_interaction_event" USING btree ("received_at");--> statement-breakpoint
CREATE INDEX "project_interaction_session_project_idx" ON "project_interaction_session" USING btree ("project_id");--> statement-breakpoint
CREATE INDEX "project_owner_updated_idx" ON "project" USING btree ("owner_user_id","updated_at");--> statement-breakpoint
CREATE INDEX "project_updated_idx" ON "project" USING btree ("updated_at");--> statement-breakpoint
CREATE INDEX "auth_session_user_idx" ON "auth_session" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "study_enrollment_run_idx" ON "study_enrollment" USING btree ("run_id");--> statement-breakpoint
CREATE UNIQUE INDEX "study_phase_run_sequence_unique" ON "study_phase_run" USING btree ("run_id","sequence_index");--> statement-breakpoint
CREATE UNIQUE INDEX "study_phase_run_project_unique" ON "study_phase_run" USING btree ("project_id");--> statement-breakpoint
CREATE INDEX "study_run_protocol_arm_idx" ON "study_run" USING btree ("mode","study_id","study_version","arm_id");--> statement-breakpoint
CREATE INDEX "study_run_owner_created_idx" ON "study_run" USING btree ("owner_user_id","created_at");--> statement-breakpoint
CREATE UNIQUE INDEX "auth_user_username_unique" ON "auth_user" USING btree ("username");--> statement-breakpoint
CREATE INDEX "auth_verification_identifier_idx" ON "auth_verification" USING btree ("identifier");