use strict;
use warnings;
use utf8;
use warnings FATAL => 'utf8';
use open ':std', ':encoding(UTF-8)';
use Test2::V0;
use Test2::Bundle::More;
use Path::Tiny;
use Finance::Tiller2QIF::Map;
use Finance::Tiller2QIF::ReadCSV;
use feature qw/signatures postderef/;

require './t/TestHelper.pm';

subtest skip_rule => sub {
  my $dbfile  = uniqfile( 'map_skip', 'sqlite3' );
  my $csvfile = uniqfile( 'map_skip', 'csv' );
  my $mapfile = uniqfile( 'map_skip', 'map' );
  my $db      = freshdb($dbfile);
  freshcsv( $csvfile,
    '04/25/2026,1,Checking,100.00,Payment,Card Payment,Credit Card Payments',
    '04/25/2026,2,Checking,50.00,Coffee,Cafe,Food',
  );
  freshmap( $mapfile,
    'category | Credit Card Payments | skip',
    'default | source',
  );
  Finance::Tiller2QIF::ReadCSV::Ingest( $csvfile, $dbfile );
  Finance::Tiller2QIF::Map::Map({db_path => $dbfile, mapfile => $mapfile});
  my %tx = map { $_->{id} => $_ }
    $db->select( 'transactions', [qw(id skipped mapped_category)] )->hashes->@*;
  is( $tx{1}{skipped},          1,     'Matched skip rule sets skipped = 1' );
  is( $tx{1}{mapped_category},  undef, 'Skipped transaction has no mapped_category' );
  is( $tx{2}{skipped},          0,     'Non-matching transaction is not skipped' );
  $db->disconnect;
};

subtest skip_default => sub {
  my $dbfile  = uniqfile( 'map_skipdef', 'sqlite3' );
  my $csvfile = uniqfile( 'map_skipdef', 'csv' );
  my $mapfile = uniqfile( 'map_skipdef', 'map' );
  my $db      = freshdb($dbfile);
  freshcsv( $csvfile,
    '04/25/2026,1,Checking,100.00,Pay,Payroll,Income',
    '04/25/2026,2,Checking,25.00,Misc,Unknown,Other',
  );
  freshmap( $mapfile,
    'category | Income | Revenues:Salary',
    'default | skip',
  );
  Finance::Tiller2QIF::ReadCSV::Ingest( $csvfile, $dbfile );
  Finance::Tiller2QIF::Map::Map({db_path => $dbfile, mapfile => $mapfile});
  my %tx = map { $_->{id} => $_ }
    $db->select( 'transactions', [qw(id skipped mapped_category)] )->hashes->@*;
  is( $tx{1}{skipped},         0,                'Matched rule overrides skip default' );
  is( $tx{1}{mapped_category}, 'Revenues:Salary', 'Matched rule sets mapped_category' );
  is( $tx{2}{skipped},         1,                'Unmatched transaction gets skip default' );
  $db->disconnect;
};

subtest skip_rerun => sub {
  my $dbfile  = uniqfile( 'map_skiprerun', 'sqlite3' );
  my $csvfile = uniqfile( 'map_skiprerun', 'csv' );
  my $mapfile = uniqfile( 'map_skiprerun', 'map' );
  my $db      = freshdb($dbfile);
  freshcsv( $csvfile, '04/25/2026,1,Checking,100.00,Payment,Card Payment,Credit Card Payments' );
  freshmap( $mapfile, 'category | Credit Card Payments | skip', 'default | source' );
  Finance::Tiller2QIF::ReadCSV::Ingest( $csvfile, $dbfile );
  Finance::Tiller2QIF::Map::Map({db_path => $dbfile, mapfile => $mapfile});
  is( $db->select( 'transactions', ['skipped'], { id => 1 } )->hash->{skipped},
    1, 'Transaction skipped after first map run' );

  # Rewrite map file without the skip rule
  path($mapfile)->spew_utf8( "default | source\n" );
  Finance::Tiller2QIF::Map::Map({db_path => $dbfile, mapfile => $mapfile});
  is( $db->select( 'transactions', ['skipped'], { id => 1 } )->hash->{skipped},
    0, 'Re-run without skip rule resets skipped to 0' );

  $db->disconnect;
};

done_testing();
unlink glob "t/tmp/t2q_*" if test_pass();
