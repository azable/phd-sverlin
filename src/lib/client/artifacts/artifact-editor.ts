/**
 * CodeMirror configuration for editable project artifacts.
 *
 * @packageDocumentation
 */

import { basicSetup, EditorView } from 'codemirror';
import { HighlightStyle, StreamLanguage, syntaxHighlighting } from '@codemirror/language';
import { haskell } from '@codemirror/legacy-modes/mode/haskell';
import type { Extension } from '@codemirror/state';
import { tags } from '@lezer/highlight';

/** Source languages supported by the project artifact editor. */
export type ArtifactLanguage = 'sverlin';

const haskellLanguage = StreamLanguage.define(haskell);
const sverlinHighlightStyle = HighlightStyle.define([
  {
    tag: [
      tags.keyword,
      tags.modifier,
      tags.controlKeyword,
      tags.definitionKeyword,
      tags.moduleKeyword
    ],
    color: 'var(--syntax-keyword)',
    fontWeight: '600'
  },
  {
    tag: [tags.variableName, tags.definition(tags.variableName), tags.function(tags.variableName)],
    color: 'var(--syntax-identifier)'
  },
  {
    tag: [tags.typeName, tags.className, tags.namespace],
    color: 'var(--syntax-type)'
  },
  {
    tag: [tags.string, tags.docString, tags.character],
    color: 'var(--syntax-string)'
  },
  {
    tag: [tags.number, tags.bool, tags.null, tags.atom],
    color: 'var(--syntax-literal)'
  },
  {
    tag: [tags.operator, tags.operatorKeyword, tags.punctuation],
    color: 'var(--syntax-operator)'
  },
  {
    tag: [tags.comment, tags.docComment],
    color: 'var(--syntax-comment)',
    fontStyle: 'italic'
  },
  {
    tag: tags.invalid,
    color: 'var(--destructive)',
    textDecoration: 'underline'
  }
]);

/** Return CodeMirror language support for a project artifact language. */
export function artifactLanguageSupport(language: ArtifactLanguage): Extension {
  switch (language) {
    case 'sverlin':
      return haskellLanguage;
  }
}

/** Build the application-aware CodeMirror color and layout theme. */
export function artifactTheme(): Extension {
  return EditorView.theme({
    '&': {
      height: '100%',
      backgroundColor: 'var(--card)',
      color: 'var(--card-foreground)',
      fontSize: '0.75rem'
    },
    '.cm-scroller': {
      overflow: 'auto',
      fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace'
    },
    '.cm-gutters': {
      backgroundColor: 'var(--muted)',
      color: 'var(--muted-foreground)',
      border: 'none'
    },
    '.cm-activeLine, .cm-activeLineGutter': {
      backgroundColor: 'color-mix(in oklab, var(--muted) 70%, transparent)'
    },
    '.cm-content': {
      padding: '0.75rem 0'
    },
    '.cm-line': {
      padding: '0 0.75rem'
    }
  });
}

/** Build the complete CodeMirror extension set for an artifact editor. */
export function artifactEditorExtensions({
  language
}: {
  language: ArtifactLanguage;
}): Extension[] {
  return [
    basicSetup,
    artifactLanguageSupport(language),
    syntaxHighlighting(sverlinHighlightStyle),
    artifactTheme()
  ];
}
