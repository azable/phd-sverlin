import type { TimelinePresentation } from '$lib/client/visualization/presentation-history';
import type { MessageContent } from '$lib/shared/projects/events/message-content';

/** Describe the currently visible visualization context with retained inline references. */
export function automaticFeedbackContext(
  presentations: readonly TimelinePresentation[]
): MessageContent {
  const visible = presentations.slice(0, 2);
  if (visible.length === 0) return [];
  const references = visible.map(({ presentation }) => [
    { type: 'presentation-ref' as const, presentationId: presentation.presentationId }
  ]);
  if (references.length === 1) {
    return [
      { type: 'markdown', text: 'Viewing ' },
      ...references[0],
      { type: 'markdown', text: '.' }
    ];
  }
  return [
    { type: 'markdown', text: 'Comparing ' },
    ...references[0],
    { type: 'markdown', text: ' with ' },
    ...references[1],
    { type: 'markdown', text: '.' }
  ];
}

/** Prepend automatic context unless the participant deliberately inserted an inline reference. */
export function feedbackSubmissionContent(
  editorContent: MessageContent,
  automaticContext: MessageContent
): MessageContent {
  if (
    automaticContext.length === 0 ||
    editorContent.some((segment) => segment.type !== 'markdown')
  ) {
    return editorContent;
  }
  const prose = editorContent
    .flatMap((segment) => (segment.type === 'markdown' ? [segment.text] : []))
    .join('\n');
  return automaticContext.map((segment, index) =>
    index === automaticContext.length - 1 && segment.type === 'markdown'
      ? { ...segment, text: `${segment.text}\n\n${prose}` }
      : segment
  );
}
