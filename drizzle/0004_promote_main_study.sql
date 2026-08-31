-- Bring pre-main-study WIP timelines to the current immutable event contract. This is a one-time
-- data rewrite rather than a runtime compatibility path: assistant identity is implied by the
-- renderer those projects already record, and a legacy render is a current single presentation.
UPDATE "project_event" AS event_row
SET "event" = jsonb_set(
	event_row."event",
	'{payload,assistantId}',
	to_jsonb(
		CASE project_row."renderer"
			WHEN 'html' THEN 'html-assistant'
			ELSE 'sverlin-assistant'
		END
	),
	true
)
FROM "project" AS project_row
WHERE event_row."project_id" = project_row."id"
	AND event_row."event"->>'type' = 'project.created'
	AND NOT (event_row."event"->'payload' ? 'assistantId');
--> statement-breakpoint
UPDATE "project_event" AS event_row
SET "event" = jsonb_set(
	jsonb_set(event_row."event", '{type}', '"visualization.presented"'::jsonb),
	'{payload}',
	jsonb_build_object(
		'displaySetId', '00000000-0000-4000-8001-' || lpad(event_row."event_id"::text, 12, '0'),
		'slot', 0,
		'presentation', event_row."event"->'payload' || jsonb_build_object(
			'presentationId', '00000000-0000-4000-8000-' || lpad(event_row."event_id"::text, 12, '0'),
			'stepSignature', 'legacy-single-presentation',
			'format', 'sverlin-ir-v1'
		)
	),
	true
)
WHERE event_row."event"->>'type' = 'visualization.rendered';
--> statement-breakpoint
-- Promote the unchanged pilot protocol to its permanent study identity while preserving runs.
UPDATE "study_run"
SET "study_id" = 'main-study'
WHERE "study_id" = 'pilot-study' AND "study_version" = 1;
