'use strict';

const ACCOUNT_COLUMNS = new Set(['account', 'category', 'mapped_category']);

// Find a single-quoted account value at the cursor. Tokenizing just enough SQL
// keeps comments, other string contents, and quoted identifiers unambiguous.
function findSqlAccountValue(text, offset) {
  const tokens = [];
  const push = (token) => { tokens.push(token); if (tokens.length > 2) tokens.shift(); };
  for (let i = 0; i < offset;) {
    if (/\s/.test(text[i])) { i++; continue; }
    if (text.startsWith('--', i)) {
      const end = text.indexOf('\n', i + 2);
      if (end < 0 || end >= offset) return null;
      i = end + 1;
      continue;
    }
    if (text.startsWith('/*', i)) {
      const end = text.indexOf('*/', i + 2);
      if (end < 0 || end + 2 > offset) return null;
      i = end + 2;
      continue;
    }
    const quote = text[i];
    if (quote === "'" || quote === '"' || quote === '`' || quote === '[') {
      const close = quote === '[' ? ']' : quote;
      const start = i + 1;
      let end = start;
      while (end < text.length) {
        if (text[end] === close) {
          if (quote !== '[' && text[end + 1] === close) { end += 2; continue; }
          break;
        }
        end++;
      }
      if (offset <= end) {
        if (quote !== "'" || tokens[1] !== '=' || !ACCOUNT_COLUMNS.has(tokens[0])) return null;
        // For an unfinished literal, replace only the typed prefix. For a
        // closed literal, replace its full value and keep the closing quote.
        return { start, end: end < text.length ? end : offset };
      }
      push(quote === "'" ? '<string>' : text.slice(start, end).toLowerCase());
      i = end + 1;
      continue;
    }
    const word = /^[a-z_][a-z_0-9]*/i.exec(text.slice(i));
    if (word) { push(word[0].toLowerCase()); i += word[0].length; }
    else { push(text[i]); i++; }
  }
  return null;
}

function sqlAccountText(name) { return name.replace(/'/g, "''"); }

function previewRows(lines) {
  const rows = [];
  for (let line = 0; line < lines.length; line++) {
    if (/^ID: .* \| Date: .* \| Account: /.test(lines[line])) {
      const row = [line];
      while (line + 1 < lines.length && /^ {4}/.test(lines[line + 1])) row.push(++line);
      rows.push(row);
    } else if (/^\s*\d{4}-\d{2}-\d{2}\s*\|/.test(lines[line])) {
      // Retained session previews from older releases are still readable.
      const row = [line];
      if (line + 1 < lines.length && /\|/.test(lines[line + 1])) row.push(++line);
      rows.push(row);
    }
  }
  return rows;
}

module.exports = { findSqlAccountValue, sqlAccountText, previewRows };
