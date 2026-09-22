'use strict';

const fs = require('fs');

// Minimal RFC4180-ish CSV parser: handles quoted fields, embedded commas,
// and "" as an escaped quote. GnuCash's CSV export needs this much (the
// Notes column routinely contains commas inside quotes).
function parseCsv(content) {
  const rows = [];
  let row = [];
  let field = '';
  let inQuotes = false;

  for (let i = 0; i < content.length; i++) {
    const c = content[i];
    if (inQuotes) {
      if (c === '"') {
        if (content[i + 1] === '"') {
          field += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field += c;
      }
      continue;
    }
    if (c === '"') {
      inQuotes = true;
    } else if (c === ',') {
      row.push(field);
      field = '';
    } else if (c === '\r') {
      // skip; \n handles the line break
    } else if (c === '\n') {
      row.push(field);
      rows.push(row);
      row = [];
      field = '';
    } else {
      field += c;
    }
  }
  if (field.length > 0 || row.length > 0) {
    row.push(field);
    rows.push(row);
  }
  return rows;
}

function readRows(filePath) {
  return parseCsv(fs.readFileSync(filePath, 'utf8'));
}

module.exports = {
  id: 'gnucash-csv',
  label: 'GnuCash chart-of-accounts CSV export',

  detect(filePath) {
    if (!/\.csv$/i.test(filePath)) return false;
    const header = readRows(filePath)[0];
    return Array.isArray(header) && header.includes('Full Account Name');
  },

  load(filePath) {
    const rows = readRows(filePath);
    if (rows.length === 0) return [];

    const header = rows[0];
    const nameIdx = header.indexOf('Full Account Name');
    if (nameIdx === -1) {
      throw new Error('no "Full Account Name" column — is this a GnuCash chart-of-accounts CSV export?');
    }
    const typeIdx = header.indexOf('Type');
    const codeIdx = header.indexOf('Account Code');
    const descIdx = header.indexOf('Description');
    const hiddenIdx = header.indexOf('Hidden');
    const placeholderIdx = header.indexOf('Placeholder');

    const accounts = [];
    for (let i = 1; i < rows.length; i++) {
      const r = rows[i];
      const name = r[nameIdx];
      if (!name) continue;

      const type = typeIdx !== -1 ? r[typeIdx] : '';
      const code = codeIdx !== -1 ? r[codeIdx] : '';
      const description = descIdx !== -1 ? r[descIdx] : '';
      const hidden = hiddenIdx !== -1 && r[hiddenIdx] === 'T';
      const placeholder = placeholderIdx !== -1 && r[placeholderIdx] === 'T';

      const tags = [];
      if (placeholder) tags.push('placeholder');
      if (hidden) tags.push('hidden');

      accounts.push({
        name,
        detail: [type, tags.join(', ')].filter(Boolean).join(' — '),
        documentation:
          [description, code ? `Account code: \`${code}\`` : ''].filter(Boolean).join('\n\n') || undefined,
      });
    }
    return accounts;
  },
};
