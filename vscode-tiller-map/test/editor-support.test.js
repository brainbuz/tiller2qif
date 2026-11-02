'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { findSqlAccountValue, sqlAccountText, previewRows } = require('../editor-support');
const manifest = require('../package.json');
const grammar = require('../syntaxes/tiller-preview.tmLanguage.json');

function atCursor(marked) {
  const offset = marked.indexOf('¦');
  const text = marked.replace('¦', '');
  const range = findSqlAccountValue(text, offset);
  return range && text.slice(range.start, range.end);
}

test('completes account columns across lines and quoted identifiers', () => {
  for (const column of ['account', 'category', 'mapped_category', '"mapped_category"', '[account]', '`category`']) {
    assert.equal(atCursor(`UPDATE transactions\nSET ${column} = 'Expenses:Fo¦od' WHERE id = '123';`), 'Expenses:Food');
  }
  assert.equal(atCursor("UPDATE transactions SET ACCOUNT =\n  '¦'"), '');
  assert.equal(atCursor("UPDATE transactions SET account = 'Assets:¦"), 'Assets:');
  assert.equal(atCursor("UPDATE transactions SET account /* note */ = '¦'"), '');
});

test('does not complete comments, non-account values, identifiers, or completed strings', () => {
  for (const sql of [
    "-- SET account = '¦'", "/* SET account = '¦' */",
    "UPDATE transactions SET memo = 'account = ¦'",
    "UPDATE transactions SET payee = '¦'", "WHERE id = '¦'",
    'UPDATE transactions SET "acc¦ount" = \'x\'',
    "UPDATE transactions SET account = 'Assets'¦", "SELECT 'account' = '¦'",
  ]) assert.equal(atCursor(sql), null, sql);
});

test('escapes apostrophes and replaces the full literal without its quotes', () => {
  assert.equal(atCursor("SET account = 'Expenses:O''B¦rien' WHERE id = '123'"), "Expenses:O''Brien");
  assert.equal(sqlAccountText("Expenses:O'Brien's Café"), "Expenses:O''Brien''s Café");
});

test('transaction decorations include all detail and continuation lines, not separators', () => {
  assert.deepEqual(previewRows([
    'ID: abc | Date: 2026-09-27 | Account: Assets:Bank',
    '    Amount:   -42.00', '    Payee:    Someone', '    Memo:     first line',
    '              continuation with | a pipe', '    Category: Expenses:Food', '',
    'ID: def | Date: 2026-09-28 | Account: Assets:Bank',
    '    Amount:   -12.00', '    Payee:    Someone else', '    Memo:     ', '    Category: Expenses:Food', '',
  ]), [[0, 1, 2, 3, 4, 5], [7, 8, 9, 10, 11]]);
  assert.deepEqual(previewRows(['2026-05-01 | -10.00 | Bank | Payee', ' Category | Memo']), [[0, 1]]);
});

test('new preview labels and headers match syntax rules', () => {
  for (const [key, line] of Object.entries({
    'block-header': 'ID: tx-α | Date: 2026-09-27 | Account: Assets:Bank',
    'block-amount': '    Amount:   -42.00', 'block-payee': '    Payee:    Café',
    'block-memo': '    Memo:     ', 'block-category': '    Category: [Old] Expenses:Food',
    'block-continuation': '              second memo line',
  })) assert.match(line, new RegExp(grammar.repository[key].match));
});

test('SQL support is explicitly scoped and suggestions enabled inside its strings', () => {
  const language = manifest.contributes.languages.find((entry) => entry.id === 'tiller2qif-sql');
  assert.deepEqual(language.extensions, ['.t2qsql']);
  assert.ok(!manifest.contributes.languages.some((entry) => entry.extensions.includes('.sql')));
  assert.ok(!manifest.activationEvents.includes('onLanguage:sql'));
  assert.equal(manifest.contributes.configurationDefaults['[tiller2qif-sql]']['editor.quickSuggestions'].strings, true);
});
