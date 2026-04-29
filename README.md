 OVERVIEW

    Convert Tiller CSV exports to QIF for import into Financial software
    like GnuCash, KMyMoney, Quicken, HomeBank, Money Manager Ex and many
    others.

SYNOPSIS

      # Command-line
      tiller2qif run --input export.csv --db tiller.sqlite3 \
                     --output import.qif [--mapfile mapping.txt]
    
      # Programmatic
      use Finance::Tiller2QIF;
    
      Finance::Tiller2QIF::ingest( input => 'export.csv', db => 'tiller.sqlite3' );
      Finance::Tiller2QIF::apply_map( db => 'tiller.sqlite3', mapfile => 'mapping.txt' );
      Finance::Tiller2QIF::emit( db => 'tiller.sqlite3', output => 'import.qif' );

INSTALLATION

 From CPAN

      cpan Finance::Tiller2QIF
      # or
      cpanm Finance::Tiller2QIF

 Perl Dependencies

    The following Perl modules are required:

      * Path::Tiny

      * Text::CSV

      * Mojo::SQLite

      * DateTime::Format::Flexible

      * Cpanel::JSON::XS

      * Getopt::Long::Descriptive

  On Debian/Ubuntu:

    All of Tiller2QIF’s dependencies are available through package
    management if you need to install to system Perl.

      sudo apt install libpath-tiny-perl libtext-csv-perl \
        libmojo-sqlite-perl libcpanel-json-xs-perl libdatetime-format-flexible-perl
      sudo cpan install Finance::Tiller2QIF

DESCRIPTION

    Tiller Money (tillerapp.com) aggregates bank and credit-card
    transactions into a Google Sheet and lets you export a CSV. This module
    ingests that CSV into a SQLite database, optionally applies a
    category-mapping file to translate Tiller's auto-assigned categories to
    match your accounts/categories, then emits a QIF file ready for import.

    The three phases can be run individually or together:

    ingest — parse the CSV and load rows into the SQLite database.

    map — apply a user-supplied mapping file that rewrites categories,
    suppresses duplicates (card-payment credits), and assigns destination
    accounts.

    emit — read unexported rows from the database and write a QIF file.

CLI COMMANDS

    run -- ingest, map, and emit in one step

        tiller2qif run --input export.csv --db tiller.sqlite3 \
                       --output import.qif [--mapfile mapping.txt]

    ingest -- load CSV into the database

        tiller2qif ingest --input export.csv --db tiller.sqlite3

    map -- apply category mapping rules

        tiller2qif map --db tiller.sqlite3 [--mapfile mapping.txt]

    emit -- write QIF from the database

        tiller2qif emit --db tiller.sqlite3 --output import.qif

    newdb -- initialise a new SQLite database

        tiller2qif newdb --db tiller.sqlite3

    newconfig -- create a starter config file

        tiller2qif newconfig [--config ~/.config/tiller2qif.conf]

OPTIONS

        "input":    "~/Downloads/mytillerdump.csv",
        "output":   "/tmp/tillerout.qif",
        "db":       "~/.data/tiller2qif.sqlite3",
        "mapfile": "~/.config/tiller.mapping"
      }

    Pass the config file with --config. Command-line options override
    config file values.

    --input CSV export from Tiller.

    --output QIF file to create.

    --db SQLite database file used to store and transform transactions
    between phases.

    --mapfile File containing category mapping rules. Optional; omitting it
    passes transactions through with their original Tiller categories.

MAPPING FILE

    The mapping file controls how Tiller categories are translated into
    destination account or category names and which transactions to
    suppress. Each non-comment line has the form:

      [AccountFilter] field | pattern | destination

    Lines beginning with # and blank lines are ignored. Rules are evaluated
    in order; the first matching rule wins and no further rules are checked
    for that transaction.

    AccountFilter (optional) — a Perl regex in square brackets that
    restricts the rule to transactions on matching accounts. Alternation
    works naturally: [Checking|Savings]. Omit to match all accounts.

    field — the transaction field to test: category, payee, memo, date, or
    amount.

    pattern — a Perl regex applied case-insensitively to the field value.

      For a simple pattern containing no |, write it as-is:

        payee | Starbucks | Expenses:Coffee

      To use regex alternation (matching either of several values), enclose
      the pattern in forward slashes:

        payee | /Starbucks|Dunkin/ | Expenses:Coffee

      To match a literal pipe character in the data, escape it with a
      backslash:

        payee | Cash\|App | Expenses:Transfers

      NULL field values (e.g. a transaction with no memo) skip the rule
      rather than matching an empty string.

    destination — the target account or category name, or one of the
    special keywords:

      source — keep the original Tiller category unchanged.

      blank — emit no category field in the QIF output.

      skip — exclude the transaction from QIF output entirely (useful for
      suppressing the credit-side of card payments that appear in both
      accounts).

      For double-entry programs such as GnuCash, destination is a full
      account name (e.g. Expenses:Groceries). For single-entry programs
      such as Quicken it is a category name.

    The optional default line sets the fallback for transactions that match
    no rule. It must appear as the last non-comment line:

      default | source

    If the default line is omitted, unmatched transactions behave as
    default | source.

 EXAMPLES

      * Map by category

        category | Groceries | Expenses:Groceries

      * Map by payee with alternation (slash-delimited pattern)

        payee | /Starbucks|Dunkin/ | Expenses:Coffee

      * Map by payee, scoped to one account

        [Checking] payee | Payroll | Income:Salary

      * Scope to multiple accounts using alternation in the account filter

        [Checking|Savings] category | Transfer | skip

      * Skip card-payment credits on the card account

        [CapitalOne] category | Transfer | skip

      * Match a literal pipe character in a payee name

        payee | Cash\|App | Expenses:Transfers

      * Suppress category in QIF (no L field)

        category | Miscellaneous | blank

      * Default: leave unmatched transactions with their Tiller category

        default | source

SEE ALSO

    Finance::Tiller2QIF::ReadCSV, Finance::Tiller2QIF::Map,
    Finance::Tiller2QIF::WriteQIF, Finance::Tiller2QIF::Util

AUTHOR

    John Karr <brainbuz@cpan.org>

LICENSE

    GPL version 3 or later.

