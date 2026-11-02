const vscode = require('vscode');
const os = require('os');
const path = require('path');
const { getLoader, detectLoader } = require('./loaders');
const { findSqlAccountValue, sqlAccountText, previewRows } = require('./editor-support');

const DESTINATION_KEYWORDS = ['source', 'blank', 'skip'];
const ROW_LANGUAGES = new Set(['tiller2qif-map', 'tiller2qif-preview']);
const RAINBOW_COLORS = [
  'rgba(217, 48, 37, 0.16)',
  'rgba(245, 124, 0, 0.16)',
  'rgba(196, 160, 0, 0.16)',
  'rgba(46, 125, 50, 0.16)',
  'rgba(25, 103, 210, 0.16)',
  'rgba(123, 31, 162, 0.16)',
];

let lastErrorKey = null; // avoid re-showing the same load error on every keystroke

function resolvePath(p) {
  if (p.startsWith('~')) {
    return path.join(os.homedir(), p.slice(1));
  }
  return p;
}

function reportError(resolved, message) {
  const key = resolved + '\0' + message;
  if (lastErrorKey === key) return;
  lastErrorKey = key;
  vscode.window.showErrorMessage(message);
}

function loadAccounts(coaPath, coaFormat) {
  const resolved = resolvePath(coaPath);

  let loader;
  if (coaFormat && coaFormat !== 'auto') {
    loader = getLoader(coaFormat);
    if (!loader) {
      reportError(resolved, `Tiller2QIF Map: unknown tiller2qifMap.coaFormat "${coaFormat}".`);
      return [];
    }
  } else {
    loader = detectLoader(resolved);
    if (!loader) {
      reportError(
        resolved,
        `Tiller2QIF Map: no loader recognizes "${resolved}". Set tiller2qifMap.coaFormat explicitly, ` +
          'or contribute a loader for this export format (see loaders/index.js).'
      );
      return [];
    }
  }

  try {
    const accounts = loader.load(resolved);
    lastErrorKey = null;
    return accounts;
  } catch (err) {
    reportError(resolved, `Tiller2QIF Map: ${loader.label} loader failed on "${resolved}": ${err.message}`);
    return [];
  }
}

// Scan `text` tracking unescaped "|" outside of /slash-delimited/ spans.
// Returns the count of such pipes and the index of the last one.
function scanFieldPipes(text) {
  let count = 0;
  let lastIndex = -1;
  let inRegex = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === '\\') {
      i++;
      continue;
    }
    if (c === '/') {
      inRegex = !inRegex;
      continue;
    }
    if (c === '|' && !inRegex) {
      count++;
      lastIndex = i;
    }
  }
  return { count, lastIndex };
}

function findDestinationRange(document, position) {
  const line = document.lineAt(position.line).text;
  let base = 0;
  let remainder = line.substring(0, position.character);

  if (/^\s*\[/.test(line)) {
    const closeIdx = line.indexOf(']');
    if (closeIdx === -1 || position.character <= closeIdx) return null; // inside/before the account filter
    base = closeIdx + 1;
    remainder = line.substring(base, position.character);
  }

  // Field name is whatever precedes the first unescaped pipe.
  let firstPipeIdx = -1;
  {
    let inRegex = false;
    for (let i = 0; i < remainder.length; i++) {
      const c = remainder[i];
      if (c === '\\') {
        i++;
        continue;
      }
      if (c === '/') {
        inRegex = !inRegex;
        continue;
      }
      if (c === '|' && !inRegex) {
        firstPipeIdx = i;
        break;
      }
    }
  }
  if (firstPipeIdx === -1) return null; // still typing the field name, not the destination

  const fieldName = remainder.slice(0, firstPipeIdx).trim().toLowerCase();
  const isDefault = fieldName === 'default';

  const { count, lastIndex } = scanFieldPipes(remainder);
  const isDestination = isDefault ? count >= 1 : count >= 2;
  if (!isDestination) return null;

  let start = lastIndex + 1;
  while (start < remainder.length && (remainder[start] === ' ' || remainder[start] === '\t')) {
    start++;
  }
  const startCol = base + start;
  return new vscode.Range(position.line, startCol, position.line, position.character);
}

function mapRows(document) {
  const rows = [];
  for (let line = 0; line < document.lineCount; line++) {
    const text = document.lineAt(line).text.trim();
    if (text && !text.startsWith('#')) rows.push([line]);
  }
  return rows;
}

function documentRows(document) {
  if (document.languageId === 'tiller2qif-preview') {
    return previewRows(Array.from({ length: document.lineCount }, (_, line) => document.lineAt(line).text));
  }
  if (document.languageId === 'tiller2qif-map') return mapRows(document);
  return [];
}

function createRowDecorations() {
  return RAINBOW_COLORS.map((color) => vscode.window.createTextEditorDecorationType({
    backgroundColor: color,
    isWholeLine: true,
  }));
}

function refreshRowDecorations(editor, decorations) {
  if (!editor || !ROW_LANGUAGES.has(editor.document.languageId)) return;

  const config = vscode.workspace.getConfiguration('tiller2qifMap');
  const mode = config.get('rowColors', 'rainbow');
  const colors = mode === 'rainbow' ? RAINBOW_COLORS.map((_, i) => i) : [];
  const ranges = decorations.map(() => []);

  if (colors.length) {
    for (const [rowIndex, lines] of documentRows(editor.document).entries()) {
      const decorationIndex = colors[rowIndex % colors.length];
      for (const line of lines) ranges[decorationIndex].push(new vscode.Range(line, 0, line, 0));
    }
  }

  decorations.forEach((decoration, index) => editor.setDecorations(decoration, ranges[index] || []));
}

function activate(context) {
  const rowDecorations = createRowDecorations();
  context.subscriptions.push(...rowDecorations);

  const decorations = rowDecorations;
  const refreshVisibleRows = () => vscode.window.visibleTextEditors.forEach((editor) => refreshRowDecorations(editor, decorations));
  context.subscriptions.push(
    vscode.window.onDidChangeActiveTextEditor(refreshVisibleRows),
    vscode.window.onDidChangeVisibleTextEditors(refreshVisibleRows),
    vscode.workspace.onDidChangeTextDocument(refreshVisibleRows),
    vscode.workspace.onDidChangeConfiguration((event) => {
      if (event.affectsConfiguration('tiller2qifMap.rowColors')) refreshVisibleRows();
    })
  );
  refreshVisibleRows();

  const provider = vscode.languages.registerCompletionItemProvider(
    'tiller2qif-map',
    {
      provideCompletionItems(document, position) {
        const range = findDestinationRange(document, position);
        if (!range) return undefined;

        const items = DESTINATION_KEYWORDS.map((kw) => {
          const item = new vscode.CompletionItem(kw, vscode.CompletionItemKind.Keyword);
          item.range = range;
          return item;
        });

        const config = vscode.workspace.getConfiguration('tiller2qifMap');
        const coaPath = config.get('coaPath', '');
        if (coaPath) {
          const coaFormat = config.get('coaFormat', 'auto');
          for (const acct of loadAccounts(coaPath, coaFormat)) {
            const item = new vscode.CompletionItem(acct.name, vscode.CompletionItemKind.EnumMember);
            item.range = range;
            if (acct.detail) item.detail = acct.detail;
            if (acct.documentation) item.documentation = new vscode.MarkdownString(acct.documentation);
            items.push(item);
          }
        }

        return items;
      },
    },
    '|', ':', ' '
  );

  context.subscriptions.push(provider);

  context.subscriptions.push(vscode.languages.registerCompletionItemProvider(
    'tiller2qif-sql',
    {
      provideCompletionItems(document, position) {
        const value = findSqlAccountValue(document.getText(), document.offsetAt(position));
        if (!value) return undefined;
        const config = vscode.workspace.getConfiguration('tiller2qifMap');
        const coaPath = config.get('coaPath', '');
        if (!coaPath) return undefined;
        const start = document.positionAt(value.start);
        const end = document.positionAt(value.end);
        if (start.line !== position.line || end.line !== position.line) return undefined;
        const range = new vscode.Range(start, end);
        return loadAccounts(coaPath, config.get('coaFormat', 'auto')).map((acct) => {
          const item = new vscode.CompletionItem(acct.name, vscode.CompletionItemKind.EnumMember);
          item.range = range;
          item.insertText = sqlAccountText(acct.name);
          item.filterText = item.insertText;
          if (acct.detail) item.detail = acct.detail;
          if (acct.documentation) item.documentation = new vscode.MarkdownString(acct.documentation);
          return item;
        });
      },
    },
    "'", ':'
  ));
}

function deactivate() {}

module.exports = { activate, deactivate };
