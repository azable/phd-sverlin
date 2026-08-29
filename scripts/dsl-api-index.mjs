import { spawn } from 'node:child_process';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const facadePath = path.join(repositoryRoot, 'compile/src/LinearTrace/Choreography.hs');
const indexPath = path.join(
  repositoryRoot,
  'src/lib/server/chat-bots/ai-assistant/dsl-api-index.md'
);
const sourceLabel = 'compile/src/LinearTrace/Choreography.hs';
const ghciMarker = '__DSL_API_ENTRY_';

function fail(message) {
  throw new Error(`DSL API documentation error: ${message}`);
}

function publicName(exportItem) {
  const withoutChildren = exportItem.replace(/\(\.\.\)$/, '');
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
  if (/^[A-Z]/.test(entry.name)) return `:info ${entry.name}`;
  if (/^[A-Za-z_]/.test(entry.name)) return `:type ${entry.name}`;
  return `:type (${entry.name})`;
}

function runGhci(commands) {
  return new Promise((resolve, reject) => {
    const child = spawn('stack', ['repl', 'compile:lib'], {
      cwd: path.join(repositoryRoot, 'compile'),
      env: process.env,
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

function normalizeGhcNames(typeInformation, entry) {
  const normalized = typeInformation
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
  return entry.name === 'Choreography'
    ? normalized
    : normalized.replace(/\bTraceBuilder\b/g, 'Choreography');
}

function compactDeclaration(lines, entry) {
  const separatedLines = lines.map((line, index) =>
    index > 0 && /^[A-Za-z_][A-Za-z0-9_']* ::/.test(line) ? `; ${line}` : line
  );
  const declaration = normalizeGhcNames(separatedLines.join(' '), entry)
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
  const declarationBlocks = rawInformation.replace(/\r/g, '').split(/\n\s*-- Defined at [^\n]+\n?/);
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

async function loadCompiledTypes(entries) {
  const commands = [
    ':set prompt ""',
    ':set prompt-cont ""',
    ':set -fno-print-explicit-foralls',
    ':module *LinearTrace.Choreography'
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
    const type = compactTypeInformation(
      rawInformation.replaceAll('LinearTrace.Choreography.', ''),
      entry
    );
    if (!type || /<interactive>|not in scope|error:/i.test(type)) {
      fail(`could not infer a public type for ${entry.export}: ${type || 'no output'}`);
    }
    return { ...entry, type };
  });
}

export function parseFacadeExports(source) {
  const moduleStart = source.indexOf('module LinearTrace.Choreography');
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
      /^\s*(?:,\s*)?([A-Za-z_][A-Za-z0-9_']*(?:\(\.\.\))?|\([^\s][^)]*\))\s*$/
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
    `This compact index combines the Haddock export documentation in \`${sourceLabel}\` with signatures inferred from the compiled facade by GHC. The facade is authoritative; the authoring guide adds composition rules and examples.`,
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
