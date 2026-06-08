import { type StyleValue } from './node.svelte';

export const styleValuesToDefaultCSSrules = (
  styleValues: Record<string, StyleValue>
): Record<string, string> => {
  const defaultCSS: Record<string, string | number> = {};
  for (const [key, value] of Object.entries(styleValues)) {
    switch (value.type) {
      case 'variable':
        // Skip, cannot determine default value for variable
        break;
      case 'constant':
        defaultCSS[key] = value.value;
        break;
      case 'fixed':
        defaultCSS[key] = value.value;
        break;
    }
  }
  return toCSSrules(defaultCSS);
};

export const toCSSrules = (style: Record<string, string | number>): Record<string, string> => {
  const rules: Record<string, string> = {};
  for (const [key, value] of Object.entries(style)) {
    const [cssKey, cssValue] = toCSSrule(key, value);
    rules[cssKey] = cssValue;
  }
  return rules;
};

export const toCSSrule = (key: string, value: number | string): [string, string] => {
  const kebabKey = key.replace(/([a-z])([A-Z])/g, '$1-$2').toLowerCase();

  if (typeof value === 'string') {
    return [kebabKey, value];
  }

  const map: Record<string, (value: number) => string> = {
    backgroundColor: (v) => v.toString(),

    width: (v) => `${v}px`,
    height: (v) => `${v}px`,
    left: (v) => `${v}px`,
    top: (v) => `${v}px`,

    minWidth: (v) => `${v}px`,
    minHeight: (v) => `${v}px`,

    padding: (v) => `${v}px`,
    paddingTop: (v) => `${v}px`,
    paddingBottom: (v) => `${v}px`,
    paddingLeft: (v) => `${v}px`,
    paddingRight: (v) => `${v}px`,

    margin: (v) => `${v}px`,
    marginTop: (v) => `${v}px`,
    marginBottom: (v) => `${v}px`,
    marginLeft: (v) => `${v}px`,
    marginRight: (v) => `${v}px`,

    fontSize: (v) => `${v}px`,

    borderWidth: (v) => `${v}px`,
    borderRadius: (v) => `${v}px`,

    zIndex: (v) => v.toString()
  };

  if (key in map) {
    return [kebabKey, map[key](value)];
  }
  throw new Error(`No CSS mapping for key: ${key}`);
};

export const toCSS = (style: Record<string, string>): string => {
  return Object.entries(style)
    .filter(([, value]) => value !== null && value !== undefined)
    .map(([key, value]) => `${key}: ${value}`)
    .join('; ');
};
