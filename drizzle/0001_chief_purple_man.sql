CREATE TABLE "study_enrollment" (
	"user_id" text PRIMARY KEY NOT NULL,
	"study_id" text NOT NULL,
	"study_version" integer NOT NULL,
	"arm_id" text NOT NULL,
	"current_phase_index" integer DEFAULT 0 NOT NULL,
	"enrolled_at" timestamp with time zone DEFAULT now() NOT NULL,
	"completed_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "study_phase_run" (
	"user_id" text NOT NULL,
	"phase_id" text NOT NULL,
	"sequence_index" integer NOT NULL,
	"kind" text NOT NULL,
	"condition_id" text,
	"renderer" text,
	"layout" text,
	"view" text,
	"project_id" varchar(128),
	"status" text DEFAULT 'ready' NOT NULL,
	"started_at" timestamp with time zone,
	"deadline_at" timestamp with time zone,
	"ended_at" timestamp with time zone,
	CONSTRAINT "study_phase_run_user_id_phase_id_pk" PRIMARY KEY("user_id","phase_id")
);
--> statement-breakpoint
ALTER TABLE "project" ADD COLUMN "renderer" text DEFAULT 'sverlin' NOT NULL;--> statement-breakpoint
ALTER TABLE "study_enrollment" ADD CONSTRAINT "study_enrollment_user_id_auth_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."auth_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "study_phase_run" ADD CONSTRAINT "study_phase_run_user_id_auth_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."auth_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "study_phase_run" ADD CONSTRAINT "study_phase_run_project_id_project_id_fk" FOREIGN KEY ("project_id") REFERENCES "public"."project"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "study_enrollment_protocol_arm_idx" ON "study_enrollment" USING btree ("study_id","study_version","arm_id");--> statement-breakpoint
CREATE UNIQUE INDEX "study_phase_run_user_sequence_unique" ON "study_phase_run" USING btree ("user_id","sequence_index");--> statement-breakpoint
CREATE UNIQUE INDEX "study_phase_run_project_unique" ON "study_phase_run" USING btree ("project_id");