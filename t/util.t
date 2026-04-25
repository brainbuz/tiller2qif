use 5.032;
use strict;
use warnings;
use Test2::V0;
use Test2::Bundle::More;
use Mojo::SQLite;
use Finance::Tiller2QIF::Util;
use Path::Tiny;

my $tmpdir = "t/tmp";
mkdir $tmpdir unless -d $tmpdir;
my $test_db = "$tmpdir/utiltest.sqlite3";

  unlink $test_db if -e $test_db;
  Finance::Tiller2QIF::Util::InitDB($test_db);

  ok(-s $test_db, "Database ${test_db} created and has non-zero size");

  my $db = Mojo::SQLite->new($test_db)->db;
  my $tables = $db->query("SELECT name FROM sqlite_master WHERE type='table'")->arrays;
  my @table_names = map { $_->[0] } @$tables;
  ok(grep { $_ eq 'transactions' } @table_names, 'transactions table exists');


  # Check columns
  my $cols = $db->query("PRAGMA table_info(transactions)")->arrays;
  my @col_names = sort ( map { $_->[1] } @$cols );
  my @expected = sort ( qw(id account date amount payee memo category exported) );

  use Data::Printer;
  say "@col_names";
  say "@expected";
  is(
    "@col_names" ,
    "@expected" ,
    'transactions table has expected columns'
  );
  $db->disconnect;

# unlink $test_db;
done_testing();
