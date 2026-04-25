use 5.034;
use strict;
use warnings;
use Test2::V0;
use Test2::Bundle::More;
use Mojo::SQLite;
use Finance::Tiller2QIF::Util;
use Path::Tiny;
# use Carp::Always;

require './t/TestHelper.pm';

my $tmpdir = "t/tmp";
mkdir $tmpdir unless -d $tmpdir;

my $test_db = "$tmpdir/utiltest.sqlite3";

unlink $test_db if -e $test_db;
Finance::Tiller2QIF::Util::InitDB($test_db);

ok( -s $test_db, "Database ${test_db} created and has non-zero size" );

my $db = Mojo::SQLite->new($test_db)->options( { sqlite_unicode => 1 } )->db;
my $tables =
  $db->query("SELECT name FROM sqlite_master WHERE type='table'")->arrays;
my @table_names = map { $_->[0] } @$tables;
ok( grep { $_ eq 'transactions' } @table_names, 'transactions table exists' );

# Check columns
my $cols      = $db->query("PRAGMA table_info(transactions)")->arrays;
my @col_names = sort { $a cmp $b } map { $_->[1] } @$cols;
my @expected  = sort { $a cmp $b } qw(id account date amount payee memo category mapped_category check_number skipped exported);

is( "@col_names", "@expected", 'transactions table has expected columns' );
$db->disconnect;

subtest 'bad db, bad conf' => sub {
  local $SIG{__WARN__} = sub {};
  my $bad_db = '/0Glunwitajwek/foo/deeply/unreachable/fake.sqlite3';
  ok( dies { Finance::Tiller2QIF::Util::InitDB($bad_db) },
    'InitDB dies on unwritable path' );

  my $bad_config = '/8Glunwitajwek/foo/deeply/unreachable/fake.conf';
  ok( dies { Finance::Tiller2QIF::Util::InitConfig($bad_config) },
    'InitConfig dies on unwritable path' );
};

done_testing();
unlink glob "t/tmp/*" if test_pass();

