'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { createRequire } = require('node:module');

function providers(coaPath) {
  const registered = new Map();
  const disposable = () => ({ dispose() {} });
  class Position { constructor(line, character) { this.line = line; this.character = character; } }
  class Range {
    constructor(...args) {
      this.start = args.length === 2 ? args[0] : new Position(args[0], args[1]);
      this.end = args.length === 2 ? args[1] : new Position(args[2], args[3]);
    }
  }
  class CompletionItem { constructor(label, kind) { this.label = label; this.kind = kind; } }
  const vscode = {
    Range, CompletionItem,
    MarkdownString: class { constructor(value) { this.value = value; } },
    CompletionItemKind: { Keyword: 1, EnumMember: 2 },
    window: {
      visibleTextEditors: [], createTextEditorDecorationType: disposable,
      onDidChangeActiveTextEditor: disposable, onDidChangeVisibleTextEditors: disposable,
      showErrorMessage(message) { throw new Error(message); },
    },
    workspace: {
      onDidChangeTextDocument: disposable, onDidChangeConfiguration: disposable,
      getConfiguration() { return { get(key, fallback) { return key === 'coaPath' ? coaPath : fallback; } }; },
    },
    languages: {
      registerCompletionItemProvider(language, provider) { registered.set(language, provider); return disposable(); },
    },
  };
  const file = path.resolve(__dirname, '../extension.js');
  const localRequire = createRequire(file);
  const module = { exports: {} };
  vm.runInNewContext(fs.readFileSync(file, 'utf8'), {
    module, require: (name) => name === 'vscode' ? vscode : localRequire(name),
  }, { filename: file });
  module.exports.activate({ subscriptions: [] });
  return registered;
}

function document(marked) {
  const offset = marked.indexOf('¦');
  const text = marked.replace('¦', '');
  const positionAt = (index) => {
    const lines = text.slice(0, index).split('\n');
    return { line: lines.length - 1, character: lines.at(-1).length };
  };
  const offsetAt = (position) => text.split('\n').slice(0, position.line)
    .reduce((sum, line) => sum + line.length + 1, 0) + position.character;
  return {
    doc: { getText: () => text, positionAt, offsetAt, lineAt: (line) => ({ text: text.split('\n')[line] }) },
    cursor: positionAt(offset), text,
  };
}

test('registered SQL provider loads the shared CoA and inserts a SQL-safe full value', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tiller-completion-'));
  try {
    const coa = path.join(dir, 'accounts.csv');
    fs.writeFileSync(coa, "Full Account Name,Type\nExpenses:O'Brien:Café,EXPENSE\nAssets:Bank,ASSET\n", 'utf8');
    const registered = providers(coa);
    assert.deepEqual([...registered.keys()], ['tiller2qif-map', 'tiller2qif-sql']);
    const sql = registered.get('tiller2qif-sql');
    const { doc, cursor, text } = document("UPDATE transactions\nSET mapped_category = 'Expenses:O¦ld' WHERE id = '123';");
    const items = sql.provideCompletionItems(doc, cursor);
    assert.deepEqual(Array.from(items, (item) => item.label), ["Expenses:O'Brien:Café", 'Assets:Bank']);
    const item = items[0];
    assert.equal(item.detail, 'EXPENSE');
    assert.equal(item.filterText, "Expenses:O''Brien:Café");
    const applied = text.slice(0, doc.offsetAt(item.range.start)) + item.insertText + text.slice(doc.offsetAt(item.range.end));
    assert.equal(applied, "UPDATE transactions\nSET mapped_category = 'Expenses:O''Brien:Café' WHERE id = '123';");
    for (const marked of ["-- mapped_category = '¦'", "SET memo = '¦'", "SET account = 'Assets:\nBank¦'"]) {
      const input = document(marked);
      assert.equal(sql.provideCompletionItems(input.doc, input.cursor), undefined);
    }
    const map = document('default | Exp¦');
    const mapItems = registered.get('tiller2qif-map').provideCompletionItems(map.doc, map.cursor);
    assert.deepEqual(Array.from(mapItems, (entry) => entry.label), ['source', 'blank', 'skip', "Expenses:O'Brien:Café", 'Assets:Bank']);
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});

test('SQL provider offers nothing without a configured chart of accounts', () => {
  const input = document("SET account = '¦'");
  assert.equal(providers('').get('tiller2qif-sql').provideCompletionItems(input.doc, input.cursor), undefined);
});
