import { basicSetup, EditorView } from 'codemirror';
import { StreamLanguage, syntaxHighlighting, defaultHighlightStyle } from '@codemirror/language';
import { haskell } from '@codemirror/legacy-modes/mode/haskell';
import type { Extension } from '@codemirror/state';

export type ArtifactLanguage = 'haskell';

const haskellLanguage = StreamLanguage.define(haskell);

export function artifactLanguageSupport(language: ArtifactLanguage): Extension {
  switch (language) {
    case 'haskell':
      return haskellLanguage;
  }
}

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

export function artifactEditorExtensions({
  language
}: {
  language: ArtifactLanguage;
}): Extension[] {
  return [
    basicSetup,
    artifactLanguageSupport(language),
    syntaxHighlighting(defaultHighlightStyle, { fallback: true }),
    artifactTheme()
  ];
}
