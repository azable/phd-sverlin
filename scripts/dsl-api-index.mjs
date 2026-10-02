import { spawn, spawnSync } from 'node:child_process';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const facadePath = path.join(repositoryRoot, 'compile/src/Sverlin.hs');
const indexPath = path.join(
  repositoryRoot,
  'src/lib/server/chat-bots/sverlin-assistant/dsl-api-index.md'
);
const sourceLabel = 'compile/src/Sverlin.hs';
const ghciMarker = '__DSL_API_ENTRY_';

function fail(message) {
  throw new Error(`DSL API documentation error: ${message}`);
}

function publicName(exportItem) {
  const withoutChildren = /^[A-Za-z_]/.test(exportItem)
    ? exportItem.replace(/\([^)]*\)$/, '')
    : exportItem;
  if (/^\([^A-Za-z0-9_].*\)$/.test(withoutChildren)) {
    return withoutChildren.slice(1, -1);
  }
  return withoutChildren;
}

function markdownDescription(description) {
  return description
    .replace(/@([^@]+)@/g, '`$1`')
    .replace(/'([A-Za-z][A-Za-z0-9_.]*|\([^' ]+\))'/g, '`$1`');
}

function ghciCommand(entry) {
  if (/^[A-Z]/.test(entry.name)) return `:info Sverlin.${entry.name}`;
  if (/^[A-Za-z_]/.test(entry.name)) return `:type Sverlin.${entry.name}`;
  return `:type (Sverlin.${entry.name})`;
}

function runGhci(commands) {
  return new Promise((resolve, reject) => {
    // GHCi loads the bundled HarfBuzz C shim into a temporary shared object.
    // On Nix, pkg-config knows its library directory but the dynamic loader
    // does not search that directory unless the library is loaded first.
    const harfbuzz = spawnSync('pkg-config', ['--variable=libdir', 'harfbuzz'], {
      encoding: 'utf8'
    });
    const preload =
      harfbuzz.status === 0 && harfbuzz.stdout.trim()
        ? path.join(harfbuzz.stdout.trim(), 'libharfbuzz.so')
        : '';
    const child = spawn('stack', ['repl', 'compile:lib'], {
      cwd: path.join(repositoryRoot, 'compile'),
      env: {
        ...process.env,
        ...(preload && {
          LD_PRELOAD: [process.env.LD_PRELOAD, preload].filter(Boolean).join(' ')
        })
      },
      stdio: ['pipe', 'pipe', 'pipe']
    });
    let stdout = '';
    let stderr = '';
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdout.on('data', (chunk) => (stdout += chunk));
    child.stderr.on('data', (chunk) => (stderr += chunk));
    child.on('error', reject);
    child.stdin.on('error', reject);
    child.on('close', (exitCode) => {
      if (exitCode === 0) resolve(stdout);
      else reject(new Error(`GHCi exited with ${exitCode}:\n${stderr.trim()}`));
    });
    child.stdin.end(commands);
  });
}

function normalizeGhcNames(typeInformation) {
  const normalized = typeInformation
    .replace(/\bP\.(?:Int|Bool|Double|String)\b/g, (name) => name.slice(2))
    .replace(/(?:ghc-internal|ghc-prim)(?:-[^:]+)?:GHC\.[A-Za-z0-9_.]+\.String/g, 'String')
    .replace(/(?:ghc-internal|ghc-prim)(?:-[^:]+)?:GHC\.[A-Za-z0-9_.]+\.Int/g, 'Int')
    .replace(/(?:ghc-internal|ghc-prim)(?:-[^:]+)?:GHC\.[A-Za-z0-9_.]+\.Double/g, 'Double')
    .replace(/(?:ghc-internal|ghc-prim)(?:-[^:]+)?:GHC\.[A-Za-z0-9_.]+\.Bool/g, 'Bool')
    .replace(/(?:ghc-internal|ghc-prim)(?:-[^:]+)?:GHC\.[A-Za-z0-9_.]+\.Maybe/g, 'Maybe')
    .replace(/(?:ghc-internal|ghc-prim)(?:-[^:]+)?:GHC\.[A-Za-z0-9_.]+\.IO/g, 'IO')
    .replace(/GHC\.Num\.Integer\.Integer/g, 'Integer')
    .replace(/ghc-internal(?:-[^:]+)?:GHC\.[A-Za-z0-9_.]+\.Rational/g, 'Rational')
    .replace(/Data\.Unrestricted\.Linear\.Internal\.Ur\.Ur/g, 'Ur')
    .replace(/\bInternal\.Typeable\b/g, 'Typeable')
    .replace(/\b(?:Constraint|Style|Variable)\./g, '')
    .replace(/\b(?:LinearTrace|Solver)(?:\.[A-Z][A-Za-z0-9_]*)+\.([A-Z][A-Za-z0-9_']*)\b/g, '$1');
  return normalized;
}

function compactDeclaration(lines, entry) {
  const separatedLines = lines.map((line, index) =>
    index > 0 && /^[A-Za-z_][A-Za-z0-9_']* ::/.test(line) ? `; ${line}` : line
  );
  const declaration = normalizeGhcNames(separatedLines.join(' '))
    .replace(/\s+/g, ' ')
    .replace(/\s+(?=(?:type(?: family)?|data|newtype|class)\s)/g, '; ')
    .replace(/^type ([A-Za-z_][A-Za-z0-9_']*) ::/, '$1 ::')
    .replace(/(^|[\s{,])\*(?=$|[\s},;])/g, '$1Type')
    .replace(/\s+;/g, ';')
    .trim();
  if (!/^[A-Za-z_][A-Za-z0-9_']*$/.test(entry.name)) return declaration;
  const selfAlias = new RegExp(
    `; type ${entry.name}(?: [A-Za-z_][A-Za-z0-9_']*)? = ${entry.name}(?: [A-Za-z_][A-Za-z0-9_']*)?$`
  );
  return declaration.replace(selfAlias, '');
}

function compactTypeInformation(rawInformation, entry) {
  const declarationBlocks = rawInformation
    .replace(/\r/g, '')
    .split(/\n\s*-- Defined (?:at|in) [^\n]+\n?/);
  const declaration = /^[A-Z]/.test(entry.name)
    ? declarationBlocks.find((block) =>
        block.split('\n').some((line) => line.trim().startsWith(`type ${entry.name} ::`))
      )
    : declarationBlocks[0];
  const lines = (declaration ?? '')
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith('type role ') && !line.startsWith('{-#'));

  if (entry.export.endsWith('(..)')) return compactDeclaration(lines, entry);

  const kindLine = lines.find((line) => line.startsWith(`type ${entry.name} ::`));
  const dataLine = lines.findIndex(
    (line) => line.startsWith(`data ${entry.name}`) || line.startsWith(`newtype ${entry.name}`)
  );
  if (dataLine >= 0) {
    return compactDeclaration(kindLine ? [kindLine] : [lines[dataLine]], entry);
  }

  const classStart = lines.findIndex((line) => line.startsWith('class '));
  if (classStart >= 0) {
    const classEnd = lines.findIndex(
      (line, index) => index >= classStart && line.endsWith('where')
    );
    const classLines = lines
      .slice(classStart, classEnd >= 0 ? classEnd + 1 : undefined)
      .map((line) => line.replace(/\s+where$/, ''));
    return compactDeclaration([...(kindLine ? [kindLine] : []), ...classLines], entry);
  }

  return compactDeclaration(lines, entry);
}

// The facade deliberately hides the closed dispatch classes behind overloaded
// operations. GHC necessarily prints those private constraints, which would
// make the authoring index look as though they were extension points. Keep the
// compiled type for ordinary exports and present the documented public forms
// for the small overloaded surface.
const publicTypeOverrides = new Map([
  ['Traceable', 'class Traceable tag where; type Payload tag'],
  [
    'Applicable1',
    'class Applicable1 operator argument where; type Apply1Result operator argument; applyPayload1 :: Payload operator %1 -> Payload argument %1 -> Payload (Apply1Result operator argument)'
  ],
  [
    'Applicable2',
    'class Applicable2 operator left right where; type Apply2Result operator left right; applyPayload2 :: Payload operator %1 -> Payload left %1 -> Payload right %1 -> Payload (Apply2Result operator left right)'
  ],
  ['>>=', '(>>=) :: builder value -> (value -> builder result) -> builder result'],
  [
    '>>',
    '(>>) :: Domain () %1 -> Domain result %1 -> Domain result; (>>) :: Program () %1 -> Program result %1 -> Program result; (>>) :: Generator value -> Generator result -> Generator result; (>>) :: Render value -> Render result -> Render result; (>>) :: TextBuilder value -> TextBuilder result -> TextBuilder result'
  ],
  ['pure', 'pure :: value -> builder value'],
  ['return', 'return :: value -> builder value'],
  ['fail', 'fail :: String -> builder value'],
  ['declareSteps', 'declareSteps :: forall steps. Domain ()'],
  [
    'variable',
    'variable @identity :: Generator value -> Domain value; variable @role :: Render role'
  ],
  [
    'create',
    'create :: Payload tag %1 -> Domain (Create tag); create :: Payload tag %1 -> Program (Create tag)'
  ],
  [
    'materialize',
    'materialize :: Kind tag -> Pending tag %1 -> Domain (Block tag); materialize :: Kind tag -> Pending tag %1 -> Program (Block tag)'
  ],
  [
    'seal',
    'seal :: Block owner %1 -> Block value %1 -> Domain (Seal owner value); seal :: Block owner %1 -> Block value %1 -> Program (Seal owner value)'
  ],
  [
    'relate',
    'relate :: RelationKind source target -> Slot source sourceValue %1 -> Slot target targetValue %1 -> Domain (Relate source sourceValue target targetValue); relate :: RelationKind source target -> Slot source sourceValue %1 -> Slot target targetValue %1 -> Program (Relate source sourceValue target targetValue)'
  ],
  [
    'Create',
    'Create :: forall {k}. k -> Type; data Create tag where; Create :: forall {k} (tag :: k). Pending tag %1 -> Create tag'
  ],
  [
    'Use',
    'Use :: forall {k}. k -> Type; data Use tag where; Use :: forall {k} (tag :: k). Payload tag %1 -> Use tag'
  ],
  [
    'Copy',
    'Copy :: forall {k}. k -> Type; data Copy tag where; Copy :: forall {k} (tag :: k). Block tag %1 -> Pending tag %1 -> Copy tag'
  ],
  [
    'Replace',
    'Replace :: forall {k}. k -> Type; data Replace tag where; Replace :: forall {k} (tag :: k). Pending tag %1 -> Replace tag'
  ],
  [
    'Apply1',
    'Apply1 :: forall {k} {k1}. k -> k1 -> Type; data Apply1 operator argument where; Apply1 :: forall {k} {k1} (operator :: k) (argument :: k1). Pending (Apply1Result operator argument) %1 -> Apply1 operator argument'
  ],
  [
    'Apply2',
    'Apply2 :: forall {k} {k1} {k2}. k -> k1 -> k2 -> Type; data Apply2 operator left right where; Apply2 :: forall {k} {k1} {k2} (operator :: k) (left :: k1) (right :: k2). Pending (Apply2Result operator left right) %1 -> Apply2 operator left right'
  ],
  [
    'Seal',
    'Seal :: forall {k} {k1}. k -> k1 -> Type; data Seal owner value where; Seal :: forall {k} {k1} (owner :: k) (value :: k1). Block owner %1 -> Slot owner value %1 -> Seal owner value'
  ],
  [
    'Unseal',
    'Unseal :: forall {k} {k1}. k -> k1 -> Type; data Unseal owner value where; Unseal :: forall {k} {k1} (owner :: k) (value :: k1). Block owner %1 -> Block value %1 -> Unseal owner value'
  ],
  [
    'Relate',
    'Relate :: forall {k} {k1} {k2} {k3}. k -> k1 -> k2 -> k3 -> Type; data Relate source sourceValue target targetValue where; Relate :: forall {k} {k1} {k2} {k3} (source :: k) (sourceValue :: k1) (target :: k2) (targetValue :: k3). Slot source sourceValue %1 -> Slot target targetValue %1 -> Relate source sourceValue target targetValue'
  ],
  [
    'select',
    'select :: Kind tag -> Render (Selected tag); select :: RelationKind source target -> Render (Relations source target)'
  ],
  [
    'node',
    'node :: Selected tag -> Render () -> Render (); node :: Render () -> Render (Selected GeneratedNode)'
  ],
  ['fragmentMany', 'fragmentMany :: forall steps. String -> TextBuilder ()'],
  ['choice', 'choice :: forall value. Render (Choice value)'],
  ['Coord', 'Coord :: Type'],
  ['Span', 'Span :: Type'],
  ['Offset', 'Offset :: Type'],
  ['Scalar', 'Scalar :: Type'],
  ['Unit', 'Unit :: Type'],
  ['Angle', 'Angle :: Type'],
  ['num', 'num :: Double -> inferred numeric role'],
  ['.+.', '(.+.) :: left -> right -> compatible result'],
  ['.-.', '(.-.) :: left -> right -> compatible result'],
  ['.*.', '(.*.) :: left -> right -> compatible result'],
  ['./.', '(./.) :: left -> right -> compatible result'],
  ['left', 'left :: Selected node -> Coord; left :: Coord -> Render ()'],
  ['top', 'top :: Selected node -> Coord; top :: Coord -> Render ()'],
  ['right', 'right :: Selected node -> Coord; right :: Coord -> Render ()'],
  ['bottom', 'bottom :: Selected node -> Coord; bottom :: Coord -> Render ()'],
  ['width', 'width :: Selected node -> Span; width :: Span -> Render ()'],
  ['height', 'height :: Selected node -> Span; height :: Span -> Render ()'],
  ['x', 'x :: Selected node -> Coord; x :: Coord -> Render ()'],
  ['y', 'y :: Selected node -> Coord; y :: Coord -> Render ()'],
  ['center', 'center :: Selected node -> Vec2 Coord; center :: Vec2 Coord -> Render ()'],
  ['size', 'size :: Selected node -> Vec2 Span'],
  ['style', 'style :: forall field input. input -> Render ()'],
  ['withoutStyle', 'withoutStyle :: forall field. Render ()'],
  ['styleOf', 'styleOf :: forall field node. Selected node -> symbolic field value'],
  ['Hsl', 'Hsl :: Angle -> Unit -> Unit -> Color'],
  ['.<=.', '(.<=.) :: left -> right -> VisualConstraint'],
  ['.>=.', '(.>=.) :: left -> right -> VisualConstraint'],
  ['.==.', '(.==.) :: left -> right -> VisualConstraint']
]);

function publicType(entry, inferredType) {
  return publicTypeOverrides.get(entry.name) ?? inferredType;
}

async function loadCompiledTypes(entries) {
  const commands = [
    ':set prompt ""',
    ':set prompt-cont ""',
    ':set -fno-print-explicit-foralls',
    // The public package is a thin re-export library, so load its compiled
    // facade rather than asking GHCi to interpret a home-module source file.
    ':module +Sverlin'
  ];
  for (const [index, entry] of entries.entries()) {
    commands.push(`:! echo ${ghciMarker}${index}__`, ghciCommand(entry));
  }
  commands.push(':quit', '');

  const output = await runGhci(commands.join('\n'));
  const markerPattern = new RegExp(`${ghciMarker}(\\d+)__\\n`, 'g');
  const matches = [...output.matchAll(markerPattern)];
  if (matches.length !== entries.length) {
    fail(`GHCi returned ${matches.length} type records for ${entries.length} exports`);
  }

  return entries.map((entry, index) => {
    const match = matches[index];
    const nextMatch = matches[index + 1];
    const rawInformation = output
      .slice(match.index + match[0].length, nextMatch?.index ?? output.length)
      .replace(/\s*Leaving GHCi\.\s*$/, '');
    const inferredType = compactTypeInformation(rawInformation.replaceAll('Sverlin.', ''), entry);
    const type = publicType(entry, inferredType);
    if (!type || /<interactive>|not in scope|error:/i.test(type)) {
      fail(`could not infer a public type for ${entry.export}: ${type || 'no output'}`);
    }
    return { ...entry, type };
  });
}

export function parseFacadeExports(source) {
  const moduleStart = source.indexOf('module Sverlin');
  if (moduleStart < 0) fail('public facade module declaration was not found');

  const exportEnd = source.indexOf('\n  ) where', moduleStart);
  if (exportEnd < 0) fail('public facade export list terminator was not found');

  const lines = source.slice(moduleStart, exportEnd).split('\n');
  const entries = [];
  let category;
  let documentation;

  for (const [offset, line] of lines.entries()) {
    const categoryMatch = line.match(/-- \* (.*?)(?:\s+#[^#]+#)?\s*$/);
    if (categoryMatch) {
      category = categoryMatch[1].trim();
      documentation = undefined;
      continue;
    }

    const documentationMatch = line.match(/^\s*(?:,\s*)?-- \|\s*(.*)$/);
    if (documentationMatch) {
      documentation = documentationMatch[1].trim();
      continue;
    }

    const continuationMatch = documentation && line.match(/^\s*--\s+(.*)$/);
    if (continuationMatch) {
      documentation = `${documentation} ${continuationMatch[1].trim()}`.trim();
      continue;
    }

    const itemMatch = line.match(
      /^\s*(?:,\s*)?([A-Za-z_][A-Za-z0-9_']*(?:\([^)]*\))?|\([^\s][^)]*\))\s*$/
    );
    if (!itemMatch) continue;

    const exportItem = itemMatch[1];
    const lineNumber = source.slice(0, moduleStart).split('\n').length + offset;
    if (!category) fail(`${exportItem} at ${sourceLabel}:${lineNumber} has no section`);
    if (!documentation) {
      fail(`${exportItem} at ${sourceLabel}:${lineNumber} has no Haddock description`);
    }

    entries.push({
      name: publicName(exportItem),
      export: exportItem,
      category,
      description: documentation
    });
    documentation = undefined;
  }

  if (entries.length === 0) fail('no explicit exports were indexed');

  const duplicateNames = entries
    .map(({ name }) => name)
    .filter((name, index, names) => names.indexOf(name) !== index);
  if (duplicateNames.length > 0) {
    fail(`duplicate public names: ${[...new Set(duplicateNames)].join(', ')}`);
  }

  return entries;
}

export function renderMarkdown(entries) {
  const sections = new Map();
  for (const entry of entries) {
    const section = sections.get(entry.category) ?? [];
    section.push(entry);
    sections.set(entry.category, section);
  }

  const output = [
    '<!-- Generated by scripts/dsl-api-index.mjs from the Haskell facade. Do not edit. -->',
    '',
    '# Public Sverlin DSL API index',
    '',
    `This compact index combines the Haddock export documentation in \`${sourceLabel}\` with public signatures checked against the compiled facade by GHC. Private closed-dispatch constraints are shown as their documented overloads. The facade and the body-only source wrapper are authoritative.`,
    ''
  ];

  for (const [category, sectionEntries] of sections) {
    output.push(`## ${category}`, '');
    for (const entry of sectionEntries) {
      output.push(
        `- \`${entry.name}\` — Type: \`${entry.type}\` — ${markdownDescription(entry.description)}`
      );
    }
    output.push('');
  }

  return `${output.join('\n').trimEnd()}\n`;
}

async function main() {
  const mode = process.argv[2];
  const source = await readFile(facadePath, 'utf8');
  const entries = await loadCompiledTypes(parseFacadeExports(source));
  const markdown = renderMarkdown(entries);

  if (mode === '--write') {
    await writeFile(indexPath, markdown);
    process.stdout.write(`Indexed ${entries.length} public DSL names in ${indexPath}\n`);
    return;
  }

  if (mode === '--check') {
    let existing;
    try {
      existing = await readFile(indexPath, 'utf8');
    } catch {
      fail(`generated index is missing; run pnpm run generate:dsl-api-index`);
    }
    if (existing !== markdown) {
      fail(`generated index is stale; run pnpm run generate:dsl-api-index`);
    }
    process.stdout.write(`Verified ${entries.length} documented public DSL names\n`);
    return;
  }

  if (mode === '--json') {
    process.stdout.write(`${JSON.stringify({ source: sourceLabel, entries }, null, 2)}\n`);
    return;
  }

  if (mode && mode !== '--markdown') {
    fail(`unknown option ${mode}; use --write, --check, --json, or --markdown`);
  }
  process.stdout.write(markdown);
}

await main();
