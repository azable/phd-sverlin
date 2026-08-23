/** Browser loading helpers for compiler-selected content-addressed fonts. */

import type { FontInstance } from '$lib/shared/visualization';

const fontLoads = new Map<string, Promise<void>>();

/** A collision-free CSS family name for one exact font resource. */
export function compilerFontFamily(resourceId: string): string {
  return `Sverlin_${resourceId.replace(/[^a-zA-Z0-9_]/g, '_')}`;
}

/** Install one exact compiler font in the document's FontFaceSet. */
export function ensureCompilerFont(font: FontInstance, resourceUrl: string): Promise<void> {
  const key = `${font.instanceResourceId}:${font.instanceStyle}:${resourceUrl}`;
  const existing = fontLoads.get(key);
  if (existing) return existing;

  const load = installCompilerFont(font, resourceUrl);
  fontLoads.set(key, load);
  return load;
}

function asyncUnavailable(): Promise<void> {
  return Promise.reject(new Error('The browser FontFace API is unavailable.'));
}

async function installCompilerFont(font: FontInstance, resourceUrl: string): Promise<void> {
  if (typeof document === 'undefined' || typeof FontFace === 'undefined') return asyncUnavailable();

  const face = new FontFace(compilerFontFamily(font.instanceResourceId), `url("${resourceUrl}")`, {
    display: 'block',
    style: font.instanceStyle,
    weight: '1 1000'
  });
  const loaded = await face.load();
  document.fonts.add(loaded);
}

/** CSS variation settings matching the compiler's explicit font axes. */
export function fontVariationSettings(font: FontInstance): string | undefined {
  if (font.instanceAxes.length === 0) return undefined;
  return font.instanceAxes.map(({ axisTag, axisValue }) => `"${axisTag}" ${axisValue}`).join(', ');
}

/** CSS feature settings matching the compiler's explicit HarfBuzz features. */
export function fontFeatureSettings(font: FontInstance): string | undefined {
  if (font.instanceFeatures.length === 0) return undefined;
  return font.instanceFeatures
    .map((feature) => {
      const [tag, value = '1'] = feature.split('=', 2);
      return `"${tag}" ${value}`;
    })
    .join(', ');
}
