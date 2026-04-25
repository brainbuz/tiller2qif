use strict;
use warnings;
use Test::More;
use Path::Tiny;
use Finance::Tiller2QIF::ReadCSV;
use Finance::Tiller2QIF::WriteQIF;

# Prepare test SQLite DB and CSV
my $test_db = "t/test.sqlite3";
my $test_csv = "t/test.csv";
my $test_qif = "t/test.qif";

# Create a simple CSV file
path($test_csv)->spew(<<'CSV');
Date,Transaction ID,Account,Amount,Description,Full Description,Category
04/24/2026,1,Checking,100.00,Deposit,Paycheck,Income
04/25/2026,2,Checking,-50.00,Withdrawal,ATM,Expense
CSV

# Create a simple SQLite DB with the right schema
unlink $test_db if -e $test_db;
my $dbh = DBI->connect("dbi:SQLite:dbname=$test_db", "", "", { RaiseError => 1, AutoCommit => 1 });
$dbh->do(q{
  CREATE TABLE transactions (
    id TEXT PRIMARY KEY,
    account TEXT,
    date TEXT,
    amount TEXT,
    payee TEXT,
    memo TEXT,
    category TEXT,
    exported BOOLEAN DEFAULT 0
  )
});
$dbh->disconnect;

# Ingest CSV into DB
Finance::Tiller2QIF::ReadCSV::Ingest($test_csv, $test_db);

# Emit QIF from DB
Finance::Tiller2QIF::WriteQIF::Emit($test_db, $test_qif);

# Check QIF output
ok(-e $test_qif, 'QIF file created');
my $qif = path($test_qif)->slurp_utf8;
like($qif, qr/Deposit/, 'QIF contains Deposit');
like($qif, qr/Withdrawal/, 'QIF contains Withdrawal');
like($qif, qr/!Account/, 'QIF contains account header');

# Clean up
unlink $test_db, $test_csv, $test_qif;
done_testing();
