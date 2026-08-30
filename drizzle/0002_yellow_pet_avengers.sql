ALTER TABLE "project_resource" ALTER COLUMN "bytes" SET NOT NULL;--> statement-breakpoint
ALTER TABLE "project_resource" DROP COLUMN "pathname";