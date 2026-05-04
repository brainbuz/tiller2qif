use strict;
use warnings;
use utf8;
use warnings FATAL => 'utf8';
use open ':std', ':encoding(UTF-8)';
use Test2::V0;
use Test2::Bundle::More;
use Test2::Tools::Exception qw/dies lives/;
use Path::Tiny;
use Finance::Tiller2QIF::Map;
use Finance::Tiller2QIF::ReadCSV;
use Finance::Tiller2QIF::Util;
use Mojo::SQLite;
use feature qw/signatures postderef/;

require './t/TestHelper.pm';

subtest no_map_file => sub {
  my $dbfile  = uniqfile( 'map_noop', 'sqlite3' );
  my $csvfile = uniqfile( 'map_noop', 'csv' );
  my $db      = freshdb($dbfile);
  freshcsv( $csvfile, '04/25/2026,1,Checking,10.00,Coffee,Corner Cafe,Food' );
  Finance::Tiller2QIF::ReadCSV::Ingest( $csvfile, $dbfile );
  Finance::Tiller2QIF::Map::Map({db_path => $dbfile});
  my $tx = $db->select( 'transactions', ['mapped_category'], { id => 1 } )->hash;
  is( $tx->{mapped_category}, undef, 'No mapping file leaves mapped_category NULL' );
  $db->disconnect;
};

subtest category_match => sub {
  my $dbfile  = uniqfile( 'map_cat', 'sqlite3' );
  my $csvfile = uniqfile( 'map_cat', 'csv' );
  my $mapfile = uniqfile( 'map_cat', 'map' );
  my $db      = freshdb($dbfile);
  freshcsv( $csvfile,
    '04/25/2026,2,Checking,10.00,Coffee,Corner Cafe,Food',
    '04/25/2026,3,Checking,50.00,Shoes,Shoe Shop,Shopping',
  );
  freshmap( $mapfile,
    'category | Food | Expenses:Food',
    'default | source',
  );
  Finance::Tiller2QIF::ReadCSV::Ingest( $csvfile, $dbfile );
  Finance::Tiller2QIF::Map::Map({db_path => $dbfile, mapfile => $mapfile});
  my @rows = $db->select( 'transactions', [qw(id mapped_category)],
    {}, { order_by => 'id' } )->hashes->@*;
  is( $rows[0]{mapped_category}, 'Expenses:Food', 'Matched category is mapped' );
  is( $rows[1]{mapped_category}, undef,           'source default leaves unmatched NULL' );
  $db->disconnect;
};

subtest blank_destination => sub {
  my $dbfile  = uniqfile( 'map_blank', 'sqlite3' );
  my $csvfile = uniqfile( 'map_blank', 'csv' );
  my $mapfile = uniqfile( 'map_blank', 'map' );
  my $db      = freshdb($dbfile);
  freshcsv( $csvfile, '04/25/2026,4,Checking,10.00,Fee,Bank Fee,Fees' );
  freshmap( $mapfile,
    'category | Fees | blank',
    'default | source',
  );
  Finance::Tiller2QIF::ReadCSV::Ingest( $csvfile, $dbfile );
  Finance::Tiller2QIF::Map::Map({db_path => $dbfile, mapfile => $mapfile});
  my $tx = $db->select( 'transactions', ['mapped_category'], { id => 4 } )->hash;
  is( $tx->{mapped_category}, '', 'blank keyword sets mapped_category to empty string' );
  $db->disconnect;
};

subtest default_blank => sub {
  my $dbfile  = uniqfile( 'map_defblank', 'sqlite3' );
  my $csvfile = uniqfile( 'map_defblank', 'csv' );
  my $mapfile = uniqfile( 'map_defblank', 'map' );
  my $db      = freshdb($dbfile);
  freshcsv( $csvfile,
    '04/25/2026,5,Checking,100.00,Pay,Payroll,Income',
    '04/25/2026,6,Checking,25.00,Misc,Unknown,Other',
  );
  freshmap( $mapfile,
    'category | Income | Revenues:Salary',
    'default | blank',
  );
  Finance::Tiller2QIF::ReadCSV::Ingest( $csvfile, $dbfile );
  Finance::Tiller2QIF::Map::Map({db_path => $dbfile, mapfile => $mapfile});
  my @rows = $db->select( 'transactions', [qw(id mapped_category)],
    {}, { order_by => 'id' } )->hashes->@*;
  is( $rows[0]{mapped_category}, 'Revenues:Salary', 'Rule match overrides blank default' );
  is( $rows[1]{mapped_category}, '',                'blank default applied to unmatched' );
  $db->disconnect;
};

subtest first_match_wins => sub {
  my $dbfile  = uniqfile( 'map_first', 'sqlite3' );
  my $csvfile = uniqfile( 'map_first', 'csv' );
  my $mapfile = uniqfile( 'map_first', 'map' );
  my $db      = freshdb($dbfile);
  freshcsv( $csvfile, '04/25/2026,7,Checking,10.00,Coffee,Cafe,Food' );
  freshmap( $mapfile,
    'category | Food     | Expenses:Food',
    'category | ^Food$   | Expenses:Dining',
    'default | source',
  );
  Finance::Tiller2QIF::ReadCSV::Ingest( $csvfile, $dbfile );
  Finance::Tiller2QIF::Map::Map({db_path => $dbfile, mapfile => $mapfile});
  my $tx = $db->select( 'transactions', ['mapped_category'], { id => 7 } )->hash;
  is( $tx->{mapped_category}, 'Expenses:Food', 'First matching rule wins' );
  $db->disconnect;
};

subtest payee_match => sub {
  my $dbfile  = uniqfile( 'map_payee', 'sqlite3' );
  my $csvfile = uniqfile( 'map_payee', 'csv' );
  my $mapfile = uniqfile( 'map_payee', 'map' );
  my $db      = freshdb($dbfile);
  freshcsv( $csvfile, '04/25/2026,8,Checking,50.00,,Amazon,Shopping' );
  freshmap( $mapfile,
    'payee | Amazon | blank',
    'default | source',
  );
  Finance::Tiller2QIF::ReadCSV::Ingest( $csvfile, $dbfile );
  Finance::Tiller2QIF::Map::Map({db_path => $dbfile, mapfile => $mapfile});
  my $tx = $db->select( 'transactions', ['mapped_category'], { id => 8 } )->hash;
  is( $tx->{mapped_category}, '', 'payee match with blank destination works' );
  $db->disconnect;
};

subtest regex_alternation => sub {
  my $dbfile  = uniqfile( 'map_alt', 'sqlite3' );
  my $csvfile = uniqfile( 'map_alt', 'csv' );
  my $mapfile = uniqfile( 'map_alt', 'map' );
  my $db      = freshdb($dbfile);
  freshcsv( $csvfile,
    '04/25/2026,1,Checking,10.00,,Cafe Alpha,Food',
    '04/25/2026,2,Checking,20.00,,Cafe Beta,Food',
    '04/25/2026,3,Checking,5.00,Gas,Shell,Auto',
  );
  freshmap( $mapfile,
    'payee | /Cafe Alpha|Cafe Beta/ | Expenses:Dining',
    'default | source',
  );
  Finance::Tiller2QIF::ReadCSV::Ingest( $csvfile, $dbfile );
  Finance::Tiller2QIF::Map::Map({db_path => $dbfile, mapfile => $mapfile});
  my @rows = $db->select( 'transactions', [qw(id mapped_category)],
    {}, { order_by => 'id' } )->hashes->@*;
  is( $rows[0]{mapped_category}, 'Expenses:Dining', 'First alternation matched' );
  is( $rows[1]{mapped_category}, 'Expenses:Dining', 'Second alternation matched' );
  is( $rows[2]{mapped_category}, undef,             'Non-matching stays NULL' );
  $db->disconnect;
};

subtest rerun_is_idempotent => sub {
  my $dbfile  = uniqfile( 'map_rerun', 'sqlite3' );
  my $csvfile = uniqfile( 'map_rerun', 'csv' );
  my $mapfile = uniqfile( 'map_rerun', 'map' );
  my $db      = freshdb($dbfile);
  freshcsv( $csvfile, '04/25/2026,12,Checking,10.00,Coffee,Cafe,Food' );
  freshmap( $mapfile,
    'category | Food | Expenses:Food',
    'default | source',
  );
  Finance::Tiller2QIF::ReadCSV::Ingest( $csvfile, $dbfile );
  Finance::Tiller2QIF::Map::Map({db_path => $dbfile, mapfile => $mapfile});
  Finance::Tiller2QIF::Map::Map({db_path => $dbfile, mapfile => $mapfile});
  my $tx = $db->select( 'transactions', ['mapped_category'], { id => 12 } )->hash;
  is( $tx->{mapped_category}, 'Expenses:Food', 'Running map twice gives same result' );
  $db->disconnect;
};

subtest invalid_field => sub {
  my $dbfile  = uniqfile( 'map_badf', 'sqlite3' );
  my $mapfile = uniqfile( 'map_badf', 'map' );
  freshdb($dbfile);
  freshmap( $mapfile, 'badfield | foo | bar' );
  ok( dies { Finance::Tiller2QIF::Map::Map({db_path => $dbfile, mapfile => $mapfile}) },
    'Unknown field name dies' );
};

subtest invalid_regex => sub {
  my $dbfile  = uniqfile( 'map_badr', 'sqlite3' );
  my $mapfile = uniqfile( 'map_badr', 'map' );
  freshdb($dbfile);
  freshmap( $mapfile, 'category | [unclosed | dest' );
  ok( dies { Finance::Tiller2QIF::Map::Map({db_path => $dbfile, mapfile => $mapfile}) },
    'Invalid regex dies' );
};

subtest case_insensitive_field => sub {
  my $dbfile  = uniqfile( 'map_cifield', 'sqlite3' );
  my $csvfile = uniqfile( 'map_cifield', 'csv' );
  my $mapfile = uniqfile( 'map_cifield', 'map' );
  my $db      = freshdb($dbfile);
  freshcsv( $csvfile, '04/25/2026,1,Checking,10.00,Coffee,Cafe,Food' );
  freshmap( $mapfile,
    'Category | Food | Expenses:Food',
    'Default | source',
  );
  Finance::Tiller2QIF::ReadCSV::Ingest( $csvfile, $dbfile );
  Finance::Tiller2QIF::Map::Map({db_path => $dbfile, mapfile => $mapfile});
  my $tx = $db->select( 'transactions', ['mapped_category'], { id => 1 } )->hash;
  is( $tx->{mapped_category}, 'Expenses:Food', 'Field name in mapping file is case-insensitive' );
  $db->disconnect;
};

subtest case_insensitive_pattern => sub {
  my $dbfile  = uniqfile( 'map_cipat', 'sqlite3' );
  my $csvfile = uniqfile( 'map_cipat', 'csv' );
  my $mapfile = uniqfile( 'map_cipat', 'map' );
  my $db      = freshdb($dbfile);
  freshcsv( $csvfile,
    '04/25/2026,1,Checking,10.00,Coffee,Cafe,FOOD',
    '04/25/2026,2,Checking,20.00,Coffee,Cafe,food',
    '04/25/2026,3,Checking,30.00,Coffee,Cafe,Food',
  );
  freshmap( $mapfile,
    'category | ^food$ | Expenses:Food',
    'default | source',
  );
  Finance::Tiller2QIF::ReadCSV::Ingest( $csvfile, $dbfile );
  Finance::Tiller2QIF::Map::Map({db_path => $dbfile, mapfile => $mapfile});
  my @rows = $db->select( 'transactions', [qw(id mapped_category)],
    {}, { order_by => 'id' } )->hashes->@*;
  is( $rows[0]{mapped_category}, 'Expenses:Food', 'Uppercase value matched by lowercase pattern' );
  is( $rows[1]{mapped_category}, 'Expenses:Food', 'Lowercase value matched by lowercase pattern' );
  is( $rows[2]{mapped_category}, 'Expenses:Food', 'Mixed-case value matched by lowercase pattern' );
  $db->disconnect;
};

subtest destination_preserves_case => sub {
  my $dbfile  = uniqfile( 'map_destcase', 'sqlite3' );
  my $csvfile = uniqfile( 'map_destcase', 'csv' );
  my $mapfile = uniqfile( 'map_destcase', 'map' );
  my $db      = freshdb($dbfile);
  freshcsv( $csvfile, '04/25/2026,1,Checking,10.00,Coffee,Cafe,food' );
  freshmap( $mapfile,
    'category | food | Expenses:Food:CafeAndDining',
    'default | source',
  );
  Finance::Tiller2QIF::ReadCSV::Ingest( $csvfile, $dbfile );
  Finance::Tiller2QIF::Map::Map({db_path => $dbfile, mapfile => $mapfile});
  my $tx = $db->select( 'transactions', ['mapped_category'], { id => 1 } )->hash;
  is( $tx->{mapped_category}, 'Expenses:Food:CafeAndDining',
    'Destination category case is preserved exactly' );
  $db->disconnect;
};

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

subtest escaped_pipe => sub {
  my $dbfile  = uniqfile( 'map_escape', 'sqlite3' );
  my $csvfile = uniqfile( 'map_escape', 'csv' );
  my $mapfile = uniqfile( 'map_escape', 'map' );
  my $db      = freshdb($dbfile);
  freshcsv( $csvfile,
    '04/25/2026,1,Checking,5.00,Cash|App Payment,Cash App,Transfers',
    '04/25/2026,2,Checking,5.00,Cash,Corner Store,Food',
    '04/25/2026,3,Checking,5.00,App Payment,App Store,Tech',
  );
  freshmap( $mapfile,
    'payee | Cash\|App Payment | Expenses:Transfers',
    'default | source',
  );
  Finance::Tiller2QIF::ReadCSV::Ingest( $csvfile, $dbfile );
  Finance::Tiller2QIF::Map::Map({db_path => $dbfile, mapfile => $mapfile});
  my %tx = map { $_->{id} => $_ }
    $db->select( 'transactions', [qw(id mapped_category)] )->hashes->@*;
  is( $tx{1}{mapped_category}, 'Expenses:Transfers',
    'Literal pipe in data matched by \| in pattern' );
  is( $tx{2}{mapped_category}, undef,
    '"Cash" alone does not match escaped-pipe pattern' );
  is( $tx{3}{mapped_category}, undef,
    '"App Payment" alone does not match escaped-pipe pattern' );
  $db->disconnect;
};

subtest account_filter => sub {
  my $dbfile  = uniqfile( 'map_acct', 'sqlite3' );
  my $csvfile = uniqfile( 'map_acct', 'csv' );
  my $mapfile = uniqfile( 'map_acct', 'map' );
  my $db      = freshdb($dbfile);
  freshcsv( $csvfile,
    '04/25/2026,1,Checking,10.00,Coffee,Cafe,Food',
    '04/25/2026,2,Savings,10.00,Coffee,Cafe,Food',
  );
  freshmap( $mapfile,
    '[Checking] category | Food | Expenses:Food',
    'default | source',
  );
  Finance::Tiller2QIF::ReadCSV::Ingest( $csvfile, $dbfile );
  Finance::Tiller2QIF::Map::Map({db_path => $dbfile, mapfile => $mapfile});
  my %tx = map { $_->{id} => $_ }
    $db->select( 'transactions', [qw(id mapped_category)] )->hashes->@*;
  is( $tx{1}{mapped_category}, 'Expenses:Food',
    'Account-filtered rule matches transaction on correct account' );
  is( $tx{2}{mapped_category}, undef,
    'Account-filtered rule does not match transaction on different account' );
  $db->disconnect;
};

subtest account_filter_alternation => sub {
  my $dbfile  = uniqfile( 'map_acctalt', 'sqlite3' );
  my $csvfile = uniqfile( 'map_acctalt', 'csv' );
  my $mapfile = uniqfile( 'map_acctalt', 'map' );
  my $db      = freshdb($dbfile);
  freshcsv( $csvfile,
    '04/25/2026,1,Checking,10.00,Coffee,Cafe,Food',
    '04/25/2026,2,Savings,10.00,Coffee,Cafe,Food',
    '04/25/2026,3,Brokerage,10.00,Coffee,Cafe,Food',
  );
  freshmap( $mapfile,
    '[Checking|Savings] category | Food | Expenses:Food',
    'default | source',
  );
  Finance::Tiller2QIF::ReadCSV::Ingest( $csvfile, $dbfile );
  Finance::Tiller2QIF::Map::Map({db_path => $dbfile, mapfile => $mapfile});
  my %tx = map { $_->{id} => $_ }
    $db->select( 'transactions', [qw(id mapped_category)] )->hashes->@*;
  is( $tx{1}{mapped_category}, 'Expenses:Food', 'Checking matches alternation filter' );
  is( $tx{2}{mapped_category}, 'Expenses:Food', 'Savings matches alternation filter' );
  is( $tx{3}{mapped_category}, undef,           'Brokerage not in filter, falls to default' );
  $db->disconnect;
};

subtest account_filter_skip => sub {
  my $dbfile  = uniqfile( 'map_acctskip', 'sqlite3' );
  my $csvfile = uniqfile( 'map_acctskip', 'csv' );
  my $mapfile = uniqfile( 'map_acctskip', 'map' );
  my $db      = freshdb($dbfile);
  freshcsv( $csvfile,
    '04/25/2026,1,Checking,-250.00,CardPymt,Target Payment,Credit Card Payment',
    '04/25/2026,2,Target RedCard,250.00,Payment Received,Target Payment,Credit Card Payment',
  );
  freshmap( $mapfile,
    'payee | CardPymt | Liabilities:CreditCards:Target',
    '[Target RedCard] category | Credit Card Payment | skip',
    'default | source',
  );
  Finance::Tiller2QIF::ReadCSV::Ingest( $csvfile, $dbfile );
  Finance::Tiller2QIF::Map::Map({db_path => $dbfile, mapfile => $mapfile});
  my %tx = map { $_->{id} => $_ }
    $db->select( 'transactions', [qw(id skipped mapped_category)] )->hashes->@*;
  is( $tx{1}{skipped},         0,                          'Checking payment not skipped' );
  is( $tx{1}{mapped_category}, 'Liabilities:CreditCards:Target',
    'Checking payment mapped to liability' );
  is( $tx{2}{skipped},         1,                          'Card-side credit skipped by account filter' );
  $db->disconnect;
};

subtest realistic_testcase => sub {
  my $dbfile  = uniqfile( 'map_real', 'sqlite3' );
  my $csvfile = 't/testcase/mapping1.csv';
  my $mapfile = 't/testcase/mapping1.map';
  my $db      = freshdb($dbfile);
  Finance::Tiller2QIF::ReadCSV::Ingest( $csvfile, $dbfile );
  Finance::Tiller2QIF::Map::Map({db_path => $dbfile, mapfile => $mapfile});
  my %tx = map { $_->{id} => $_ }
    $db->select( 'transactions', [qw(id payee mapped_category)] )->hashes->@*;
  is( $tx{TXN001}{mapped_category}, 'Expenses:Entertainment:Streaming Services',
    'Tidal.com matches payee pattern' );
  is( $tx{TXN002}{mapped_category}, 'Expenses:Medical Expenses',
    'Pharmacy matches category pattern' );
  is( $tx{TXN003}{mapped_category}, 'Expenses:Groceries',
    'Groceries category remapped to Expenses:Groceries' );
  is( $tx{TXN004}{mapped_category}, undef,
    'Kino Entertainment doesnt match and is defaulted' );
  $db->disconnect;
};

my $wildcarddb = q{
  INSERT INTO transactions
  (id, account, date, amount, payee, memo, category, mapped_category, check_number, skipped, exported)
  VALUES
  ('X2343', 'DINERS CLUB', '2024-11-14', 88.22, 'Pennsylvania Wine and Spirits Store 752', '', 'Groceries', '', '', 0, 0),
  ('EERWOWWS71Y', 'AMERICAN EXPRESS - 9377', '2024-11-14', 414.85, 'Toodles Stationary', '', 'Incorrect', '', '', 0, 0),
  ('78344FIOD', 'BANK OF GOTHAM - 4499', '2024-11-14', 88.22, 'Pennsylvania Wine and Spirits Store 752', '', 'Groceries', '', '', 0, 0),
  ('1654', 'TOTALLUSH STORE CARD', '2024-11-14', 79.16, 'TL Outlet Wilmington, DE', 'Jack Daniels Sale', 'Restaurants', '', '', 0, 0),
  ('1965', 'TOTALLUSH STORE CARD', '2024-11-14', 62.18, 'TL Concord Pike Wilmington, DE', 'Best Single Malt Selection in Delaware', 'Groceries', '', '', 0, 0),
  ('78267FIOD', 'BANK OF GOTHAM - 4499', '2024-11-14', 4265.21, 'Gotham Mortgage & Usury', '', 'XFER', '', '', 0, 0)
  ;
};

my $wildcardmap = q{
  [totallush] payee | * | Expenses:Alcohol
  payee | toodles | Expenses:Office Supply
  [DINERS CLUB] category | /*/ | Expenses:Restaurants
  default | uncategorized
};

subtest wildcard_on_field => sub {
  my $dbfile  = uniqfile( 'wildcard_on_field', 'sqlite3' );
  my $mapfile = uniqfile( 'wildcard_on_field', 'map' );
  my $db      = freshdb($dbfile);
  $db->query($wildcarddb);
  freshmap( $mapfile, $wildcardmap );
  Finance::Tiller2QIF::Map::Map({db_path => $dbfile, mapfile => $mapfile});
  my %tx = map { $_->{id} => $_ }
    $db->select( 'transactions', [qw(id account payee category mapped_category)],
      {}, { order_by => 'id' } )->hashes->@*;

  is( $tx{'X2343'}{mapped_category}, 'Expenses:Restaurants',
    'DINERS CLUB wildcard on category matches any category value' );
  is( $tx{'EERWOWWS71Y'}{mapped_category}, 'Expenses:Office Supply',
    'toodles payee matches case-insensitive' );
  is( $tx{'78344FIOD'}{mapped_category}, 'uncategorized',
    'BANK OF GOTHAM transaction does not match any rules' );
  is( $tx{'1654'}{mapped_category}, 'Expenses:Alcohol',
    'TOTALLUSH account wildcard on payee matches' );
  is( $tx{'1965'}{mapped_category}, 'Expenses:Alcohol',
    'TOTALLUSH account wildcard on payee matches again' );
  is( $tx{'78267FIOD'}{mapped_category}, 'uncategorized',
    'BANK OF GOTHAM XFER transaction does not match any rules' );
  $db->disconnect;
};

done_testing();

unlink glob "t/tmp/t2q_*" if test_pass();