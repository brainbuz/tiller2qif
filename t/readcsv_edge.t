
use strict;
use warnings;
use Test2::V0;
use Test2::Bundle::More;
use Test2::Tools::Warnings  qw/warns warning warnings no_warnings/;
use Test2::Tools::Exception qw/dies lives/;
use Path::Tiny;
use Finance::Tiller2QIF::ReadCSV;
use Finance::Tiller2QIF::WriteQIF;
use Finance::Tiller2QIF::Util;
use Mojo::SQLite;
use feature qw/signatures postderef/;

# use Data::Printer;

my $tmpdir = "t/tmp";
mkdir $tmpdir unless -d $tmpdir;

my $file_counter = 0;
sub uniqfile ($base, $ext) {
  $file_counter++;
  return "$tmpdir/${base}_$file_counter.$ext";
}

sub freshdb ( $newdb ) {
  unlink $newdb if -e $newdb;
  Finance::Tiller2QIF::Util::InitDB($newdb);
  Mojo::SQLite->new($newdb)->db;
}

sub freshcsv ( $csvfile, @lines ) {
  # put header at the front
  unshift @lines,
    'Date,Transaction ID,Account,Amount,Description,Full Description,Category';
  push @lines, '';
  path($csvfile)->spew( join( "\n", @lines ) );
}

subtest malformed_date => sub {
  my $dbfile = uniqfile('malformed_date', 'sqlite3');
  my $csvfile = uniqfile('malformed_date', 'csv');
  my $db = freshdb($dbfile);
  freshcsv($csvfile, 'BADDATE,1,Checking,100.00,Deposit,Paycheck,Income');

  Finance::Tiller2QIF::ReadCSV::Ingest($csvfile, $dbfile);

  like(
    warning { Finance::Tiller2QIF::ReadCSV::Ingest($csvfile, $dbfile) },
    qr/Could not parse date/,
    "Got expected warning"
  );
  my $results = $db->select('transactions', ['id'], { id => 1 })->arrays;
  is(scalar(@$results), 0, 'skipped record not in database');
  $db->disconnect;
  # unlink $dbfile, $csvfile;
};


subtest missing_amount => sub {
  my $dbfile = uniqfile('missing_amount', 'sqlite3');
  my $csvfile = uniqfile('missing_amount', 'csv');
  my $db = freshdb($dbfile);
  freshcsv($csvfile, '4/25/2026,2,Checking,,Withdrawal,ATM,Expense');
  ok(lives { Finance::Tiller2QIF::ReadCSV::Ingest($csvfile, $dbfile) },
    'Missing amount does not crash');
  $db->disconnect;
  # unlink $dbfile, $csvfile;
};

subtest missing_transaction_id => sub {
  my $dbfile = uniqfile('missing_id', 'sqlite3');
  my $csvfile = uniqfile('missing_id', 'csv');
  my $db = freshdb($dbfile);
  freshcsv($csvfile, '04/25/2026,,Checking,10.00,Withdrawal,ATM,Expense');
  ok(lives { Finance::Tiller2QIF::ReadCSV::Ingest($csvfile, $dbfile) },
    'Missing Transaction ID is not fatal');
  my $results = $db->select('transactions', '*')->arrays;
  is(scalar(@$results), 0, 'Missing Transaction ID is skipped');
  $db->disconnect;
  # unlink $dbfile, $csvfile;
};

subtest extra_columns => sub {
  my $dbfile = uniqfile('extra_columns', 'sqlite3');
  my $csvfile = uniqfile('extra_columns', 'csv');
  freshdb($dbfile);
  my @lines = (
    'Date,Transaction ID,Account,Amount,Description,Full Description,Category,Extra',
    '04/25/2026,3,Checking,10.00,Withdrawal,ATM,Expense,foo',
    '03/25/2026,4,Checking,10.00,Withdrawal,ATM,Expense,foo',
    ''
  );
  path($csvfile)->spew(join("\n", @lines));
  Finance::Tiller2QIF::ReadCSV::Ingest($csvfile, $dbfile);
  my $db = Mojo::SQLite->new($dbfile)->db;
  my $results = $db->select('transactions', '*')->arrays;
  is(scalar(@$results), 2, 'Transaction written even with extra columns');
  $db->disconnect;
  unlink $dbfile, $csvfile;
};


subtest empty_file => sub {
  my $dbfile = uniqfile('empty_file', 'sqlite3');
  my $csvfile = uniqfile('empty_file', 'csv');
  freshdb($dbfile);
  path($csvfile)->spew("");
  ok(!eval { Finance::Tiller2QIF::ReadCSV::Ingest($csvfile, $dbfile); 1 }, 'Empty file dies as expected');
  unlink $dbfile, $csvfile;

};


done_testing();
