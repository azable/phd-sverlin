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
INSERT INTO "study_run" (
	"mode", "owner_user_id", "study_id", "study_version", "arm_id",
	"current_phase_index", "started_at", "completed_at", "created_at"
)
SELECT
	'participant', e."user_id", e."study_id", e."study_version", e."arm_id",
	e."current_phase_index",
	CASE
		WHEN e."current_phase_index" > 0 OR e."completed_at" IS NOT NULL OR EXISTS (
			SELECT 1 FROM "study_phase_run" p WHERE p."user_id" = e."user_id"
		)
		THEN COALESCE(
			(
				SELECT MIN(COALESCE(p."started_at", p."ended_at"))
				FROM "study_phase_run" p
				WHERE p."user_id" = e."user_id"
			),
			e."enrolled_at"
		)
		ELSE NULL
	END,
	e."completed_at", e."enrolled_at"
FROM "study_enrollment" e;
--> statement-breakpoint
ALTER TABLE "study_enrollment" ADD COLUMN "run_id" uuid;
--> statement-breakpoint
ALTER TABLE "study_phase_run" ADD COLUMN "run_id" uuid;
--> statement-breakpoint
ALTER TABLE "study_phase_run" ADD COLUMN "end_reason" text;
--> statement-breakpoint
UPDATE "study_enrollment" e
SET "run_id" = r."id"
FROM "study_run" r
WHERE r."mode" = 'participant' AND r."owner_user_id" = e."user_id";
--> statement-breakpoint
UPDATE "study_phase_run" p
SET
	"run_id" = e."run_id",
	"status" = CASE WHEN p."status" = 'completed' THEN 'completed' ELSE 'active' END,
	"end_reason" = CASE
		WHEN p."status" = 'completed' AND p."kind" = 'task' THEN 'deadline'
		WHEN p."status" = 'completed' THEN 'continued'
		ELSE NULL
	END
FROM "study_enrollment" e
WHERE e."user_id" = p."user_id";
--> statement-breakpoint
ALTER TABLE "study_phase_run" DROP CONSTRAINT "study_phase_run_user_id_auth_user_id_fk";
--> statement-breakpoint
DROP INDEX "study_enrollment_protocol_arm_idx";
--> statement-breakpoint
DROP INDEX "study_phase_run_user_sequence_unique";
--> statement-breakpoint
ALTER TABLE "study_phase_run" DROP CONSTRAINT "study_phase_run_user_id_phase_id_pk";
--> statement-breakpoint
ALTER TABLE "study_enrollment" ALTER COLUMN "run_id" SET NOT NULL;
--> statement-breakpoint
ALTER TABLE "study_phase_run" ALTER COLUMN "run_id" SET NOT NULL;
--> statement-breakpoint
ALTER TABLE "study_phase_run" ALTER COLUMN "status" SET DEFAULT 'active';
--> statement-breakpoint
ALTER TABLE "study_phase_run" ADD CONSTRAINT "study_phase_run_run_id_phase_id_pk" PRIMARY KEY("run_id","phase_id");
--> statement-breakpoint
ALTER TABLE "study_run" ADD CONSTRAINT "study_run_owner_user_id_auth_user_id_fk" FOREIGN KEY ("owner_user_id") REFERENCES "public"."auth_user"("id") ON DELETE cascade ON UPDATE no action;
--> statement-breakpoint
CREATE INDEX "study_run_protocol_arm_idx" ON "study_run" USING btree ("mode","study_id","study_version","arm_id");
--> statement-breakpoint
CREATE INDEX "study_run_owner_created_idx" ON "study_run" USING btree ("owner_user_id","created_at");
--> statement-breakpoint
ALTER TABLE "study_enrollment" ADD CONSTRAINT "study_enrollment_run_id_study_run_id_fk" FOREIGN KEY ("run_id") REFERENCES "public"."study_run"("id") ON DELETE cascade ON UPDATE no action;
--> statement-breakpoint
ALTER TABLE "study_phase_run" ADD CONSTRAINT "study_phase_run_run_id_study_run_id_fk" FOREIGN KEY ("run_id") REFERENCES "public"."study_run"("id") ON DELETE cascade ON UPDATE no action;
--> statement-breakpoint
CREATE INDEX "study_enrollment_run_idx" ON "study_enrollment" USING btree ("run_id");
--> statement-breakpoint
CREATE UNIQUE INDEX "study_phase_run_sequence_unique" ON "study_phase_run" USING btree ("run_id","sequence_index");
--> statement-breakpoint
ALTER TABLE "study_enrollment" DROP COLUMN "study_id";
--> statement-breakpoint
ALTER TABLE "study_enrollment" DROP COLUMN "study_version";
--> statement-breakpoint
ALTER TABLE "study_enrollment" DROP COLUMN "arm_id";
--> statement-breakpoint
ALTER TABLE "study_enrollment" DROP COLUMN "current_phase_index";
--> statement-breakpoint
ALTER TABLE "study_enrollment" DROP COLUMN "completed_at";
--> statement-breakpoint
ALTER TABLE "study_phase_run" DROP COLUMN "user_id";
--> statement-breakpoint
ALTER TABLE "study_enrollment" ADD CONSTRAINT "study_enrollment_run_id_unique" UNIQUE("run_id");
