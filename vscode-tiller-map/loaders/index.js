'use strict';

/*
 * Chart-of-accounts loader contract
 * ----------------------------------
 * A loader normalizes one financial program's account export into the flat
 * list the completion provider offers for a map rule's destination column.
 * Tiller2QIF itself only ever reads GnuCash exports, so only gnucash-csv.js
 * is implemented here — but the destination column is free-form text for
 * any double-entry or category system, so this is meant to be extended.
 *
 * To add support for another program's export, drop a new file in this
 * directory exporting:
 *
 *   id       - stable string identifying the loader, used by the
 *              tiller2qifMap.coaFormat setting (e.g. "quicken-qif")
 *   label    - human-readable name, used in error messages
 *   detect(filePath) -> boolean
 *              Cheap heuristic used only in "auto" format mode: return
 *              true if this loader can probably handle the file. Checking
 *              the extension and/or peeking at a header row is enough —
 *              it doesn't need to be exact, just cheap and not a false
 *              positive against the other registered loaders.
 *   load(filePath) -> Account[]
 *              Parse the file and return accounts as:
 *                { name: string, detail?: string, documentation?: string }
 *              `name` is inserted verbatim as the destination text, so it
 *              must be the full account/category path exactly as your
 *              program's users would type it in a map rule. `detail` and
 *              `documentation` (markdown) are free-form and shown in the
 *              completion list and on hover; omit either if your export
 *              has nothing useful for it.
 *              Throw with a descriptive message on a malformed file —
 *              the caller surfaces it to the user.
 *
 * Then register the loader below, and add its `id` to the
 * tiller2qifMap.coaFormat enum in package.json.
 */

const loaders = [require('./gnucash-csv')];

function getLoader(id) {
  return loaders.find((l) => l.id === id);
}

function detectLoader(filePath) {
  return loaders.find((l) => {
    try {
      return l.detect(filePath);
    } catch {
      return false;
    }
  });
}

module.exports = { loaders, getLoader, detectLoader };
