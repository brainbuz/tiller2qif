use strict;
use warnings;
use utf8;
use warnings FATAL => 'utf8';
use open ':std', ':encoding(UTF-8)';
use Test2::V0;
use Test2::Bundle::More;
use Test2::Tools::Exception qw/dies lives/;
use Path::Tiny;
use Finance::Tiller2QIF;
use Finance::Tiller2QIF::Util;
use Mojo::SQLite;
use feature qw/signatures postderef/;

no warnings 'experimental::try';
use feature 'try';

require './t/TestHelper.pm';

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

subtest api_ingest => sub {
  my $dbfile  = uniqfile( 'ingest', 'sqlite3' );
  my $csvfile = uniqfile( 'ingest', 'csv' );
  my $db      = freshdb($dbfile);
  freshcsv( $csvfile,
    '04/25/2026,1,Checking,100.00,Deposit,Paycheck,Income',
    '04/25/2026,2,Checking,-50.00,Coffee,Cafe,Food',
  );
  ok( lives { Finance::Tiller2QIF::ingest( input => $csvfile, db => $dbfile ) },
    'ingest() lives' );
  is( $db->select( 'transactions', ['id'] )->arrays->@*, 2,
    'ingest() loaded two rows' );
  $db->disconnect;
};

subtest api_apply_map => sub {
  my $dbfile  = uniqfile( 'map', 'sqlite3' );
  my $csvfile = uniqfile( 'map', 'csv' );
  my $mapfile = uniqfile( 'map', 'map' );
  my $db      = freshdb($dbfile);
  freshcsv( $csvfile, '04/25/2026,1,Checking,100.00,Deposit,Paycheck,Income' );
  freshmap( $mapfile,
    'category | Income | Income:Salary',
    'default | source',
  );
  Finance::Tiller2QIF::ingest( input => $csvfile, db => $dbfile );
  ok( lives { Finance::Tiller2QIF::apply_map( db => $dbfile, mapfile => $mapfile ) },
    'apply_map() lives' );
  is( $db->select( 'transactions', ['mapped_category'], { id => 1 } )->hash->{mapped_category},
    'Income:Salary', 'apply_map() wrote mapped_category' );
  $db->disconnect;
};

subtest api_emit => sub {
  my $dbfile  = uniqfile( 'emit', 'sqlite3' );
  my $csvfile = uniqfile( 'emit', 'csv' );
  my $qiffile = uniqfile( 'emit', 'qif' );
  my $db      = freshdb($dbfile);
  freshcsv( $csvfile, '04/25/2026,1,Checking,100.00,Deposit,Paycheck,Income' );
  Finance::Tiller2QIF::ingest( input => $csvfile, db => $dbfile );
  ok( lives { Finance::Tiller2QIF::emit( db => $dbfile, output => $qiffile ) },
    'emit() lives' );
  ok( -e $qiffile, 'emit() created QIF file' );
  like( path($qiffile)->slurp_utf8, qr/PDeposit/, 'emitted QIF contains payee' );
  $db->disconnect;
};

subtest api_run => sub {
  my $dbfile  = uniqfile( 'run', 'sqlite3' );
  my $csvfile = uniqfile( 'run', 'csv' );
  my $mapfile = uniqfile( 'run', 'map' );
  my $qiffile = uniqfile( 'run', 'qif' );
  freshdb($dbfile)->disconnect;
  freshcsv( $csvfile, '04/25/2026,1,Checking,50.00,Deposit,Paycheck,Income' );
  freshmap( $mapfile,
    'category | Income | Income:Salary',
    'default | blank',
  );
  ok( lives {
    Finance::Tiller2QIF::run(
      input   => $csvfile,
      db      => $dbfile,
      mapfile => $mapfile,
      output  => $qiffile,
    )
  }, 'run() lives' );
  like( path($qiffile)->slurp_utf8, qr/LIncome:Salary/, 'run() QIF has mapped category' );
};

# ---------------------------------------------------------------------------
# run_cli dispatch — local @ARGV overrides argument list for each call
# ---------------------------------------------------------------------------

subtest cli_unknown_command => sub {
  local @ARGV = ('notacommand');
  ok( dies { Finance::Tiller2QIF::run_cli() }, 'Unknown command dies' );
};

subtest cli_missing_command => sub {
  local @ARGV = ();
  like(
    dies { Finance::Tiller2QIF::run_cli() },
    qr/Command Missing!/,
    'Missing command shows clear error message'
  );
};

subtest cli_missing_db => sub {
  local @ARGV = ( 'ingest', '--input', 'x.csv' );
  ok( dies { Finance::Tiller2QIF::run_cli() }, 'Missing --db dies' );
};

subtest cli_missing_input => sub {
  local @ARGV = ( 'ingest', '--db', 'x.sqlite3' );
  ok( dies { Finance::Tiller2QIF::run_cli() }, 'Missing --input for ingest dies' );
};

subtest cli_missing_output => sub {
  local @ARGV = ( 'emit', '--db', 'x.sqlite3' );
  ok( dies { Finance::Tiller2QIF::run_cli() }, 'Missing --output for emit dies' );
};

subtest cli_newdb_missing_db => sub {
  local @ARGV = ('newdb');
  ok( dies { Finance::Tiller2QIF::run_cli() }, 'newdb without --db dies' );
};

subtest cli_newconfig_missing_config => sub {
  local @ARGV = ('newconfig');
  ok( dies { Finance::Tiller2QIF::run_cli() }, 'newconfig without --config dies' );
};

subtest cli_newdb => sub {
  my $dbfile = uniqfile( 'cli_newdb', 'sqlite3' );
  local @ARGV = ( 'newdb', '--db', $dbfile );
  ok( lives { Finance::Tiller2QIF::run_cli() }, 'newdb with --db returns normally' );
  ok( -s $dbfile, 'newdb created the database file' );
};

subtest cli_run => sub {
  my $dbfile  = uniqfile( 'cli_run', 'sqlite3' );
  my $csvfile = uniqfile( 'cli_run', 'csv' );
  my $qiffile = uniqfile( 'cli_run', 'qif' );
  freshdb($dbfile)->disconnect;
  freshcsv( $csvfile, '04/25/2026,1,Checking,75.00,Deposit,Salary,Income' );
  local @ARGV = ( 'run', '--input', $csvfile, '--db', $dbfile, '--output', $qiffile );
  ok( lives { Finance::Tiller2QIF::run_cli() }, 'cli run returns normally' );
  ok( -e $qiffile, 'cli run produced QIF file' );
};

subtest cli_ingest_then_emit => sub {
  my $dbfile  = uniqfile( 'cli_ie', 'sqlite3' );
  my $csvfile = uniqfile( 'cli_ie', 'csv' );
  my $qiffile = uniqfile( 'cli_ie', 'qif' );
  freshdb($dbfile)->disconnect;
  freshcsv( $csvfile, '04/25/2026,1,Checking,30.00,Coffee,Cafe,Food' );

  { local @ARGV = ( 'ingest', '--input', $csvfile, '--db', $dbfile );
    ok( lives { Finance::Tiller2QIF::run_cli() }, 'cli ingest returns normally' ); }

  { local @ARGV = ( 'emit', '--db', $dbfile, '--output', $qiffile );
    ok( lives { Finance::Tiller2QIF::run_cli() }, 'cli emit returns normally' ); }

  like( path($qiffile)->slurp_utf8, qr/PCoffee/, 'two-phase cli produced QIF' );
};

subtest cli_run_verbose => sub {
  my $dbfile  = uniqfile( 'cli_runv', 'sqlite3' );
  my $qiffile = uniqfile( 'cli_runv', 'qif' );
  freshdb($dbfile)->disconnect;
  local @ARGV = (
    'run',
    '--input',   't/testcase/mapping1.csv',
    '--db',      $dbfile,
    '--output',  $qiffile,
    '--mapfile', 't/testcase/mapping1.map',
    '--verbose',
  );
  my $out = '';
  ok( lives { open( local *STDOUT, '>', \$out ); Finance::Tiller2QIF::run_cli() },
    'cli run --verbose returns normally' );
  ok( -e $qiffile, 'cli run --verbose produced QIF file' );
  like( $out, qr/Ingesting CSV/,    'verbose output mentions ingesting' );
  like( $out, qr/Applying mapping/, 'verbose output mentions mapping' );
  like( $out, qr/Writing QIF/,      'verbose output mentions writing' );
};

subtest cli_newdb_verbose => sub {
  my $dbfile = uniqfile( 'cli_newdbv', 'sqlite3' );
  local @ARGV = ( 'newdb', '--db', $dbfile, '--verbose' );
  my $out = '';
  ok( lives { open( local *STDOUT, '>', \$out ); Finance::Tiller2QIF::run_cli() },
    'newdb --verbose returns normally' );
  like( $out, qr/Creating database/, 'verbose newdb output mentions creating' );
};

subtest cli_newconfig_verbose => sub {
  my $cfgfile = uniqfile( 'cli_newcfgv', 'json' );
  local @ARGV = ( 'newconfig', '--config', $cfgfile, '--verbose' );
  my $out = '';
  ok( lives { open( local *STDOUT, '>', \$out ); Finance::Tiller2QIF::run_cli() },
    'newconfig --verbose returns normally' );
  like( $out, qr/Creating config/, 'verbose newconfig output mentions creating' );
};

subtest cli_checkconfig => sub {
  my $dbfile  = uniqfile( 'cli_chkcfg', 'sqlite3' );
  my $csvfile = uniqfile( 'cli_chkcfg', 'csv' );
  my $qiffile = uniqfile( 'cli_chkcfg', 'qif' );
  freshdb($dbfile)->disconnect;
  freshcsv( $csvfile, '04/25/2026,1,Checking,10.00,Test,Test,Food' );

  # checkconfig command reaches line 162 via $cmd =~ /^checkconfig/
  local @ARGV = (
    'checkconfig',
    '--db',     $dbfile,
    '--input',  $csvfile,
    '--output', $qiffile,
  );
  my $out = '';
  ok( lives { open( local *STDOUT, '>', \$out ); Finance::Tiller2QIF::run_cli() },
    'checkconfig returns normally' );
  like( $out, qr/db\s*:/, 'checkconfig output lists db option' );
};

subtest cli_emit_verbose_checkconfig => sub {
  my $dbfile  = uniqfile( 'cli_emitv', 'sqlite3' );
  my $csvfile = uniqfile( 'cli_emitv', 'csv' );
  my $qiffile = uniqfile( 'cli_emitv', 'qif' );
  freshdb($dbfile)->disconnect;
  freshcsv( $csvfile, '04/25/2026,1,Checking,20.00,Test,Test,Food' );
  Finance::Tiller2QIF::ingest( input => $csvfile, db => $dbfile );

  # --verbose on emit reaches line 162 via $opt->verbose (non-run command)
  local @ARGV = ( 'emit', '--db', $dbfile, '--output', $qiffile, '--verbose' );
  my $out = '';
  ok( lives { open( local *STDOUT, '>', \$out ); Finance::Tiller2QIF::run_cli() },
    'emit --verbose returns normally' );
  like( $out, qr/db\s*:/, 'emit --verbose output lists db option via CheckConfig' );
};

subtest cli_run_checkpoints => sub {
  my $dbfile  = uniqfile( 'cli_ckpt_run', 'sqlite3' );
  my $csvfile = uniqfile( 'cli_ckpt_run', 'csv' );
  my $qiffile = uniqfile( 'cli_ckpt_run', 'qif' );
  freshdb($dbfile)->disconnect;
  freshcsv( $csvfile, '04/25/2026,1,Checking,10.00,Test,Test,Food' );
  local @ARGV = ( 'run', '--input', $csvfile, '--db', $dbfile, '--output', $qiffile );
  ok( lives { Finance::Tiller2QIF::run_cli() }, 'run returns normally' );
  my @copies = glob( $dbfile . '*' );
  ok( @copies > 1, 'run created a checkpoint copy of the database' );
};

subtest cli_checkpoint_flag => sub {
  my $dbfile  = uniqfile( 'cli_ckpt_flag', 'sqlite3' );
  my $csvfile = uniqfile( 'cli_ckpt_flag', 'csv' );
  freshdb($dbfile)->disconnect;
  freshcsv( $csvfile, '04/25/2026,1,Checking,10.00,Test,Test,Food' );
  local @ARGV = ( 'ingest', '--input', $csvfile, '--db', $dbfile, '--checkpoint' );
  ok( lives { Finance::Tiller2QIF::run_cli() }, 'ingest --checkpoint returns normally' );
  my @copies = glob( $dbfile . '*' );
  ok( @copies > 1, '--checkpoint created a checkpoint copy of the database' );
};

subtest cli_clean_missing_db => sub {
  local @ARGV = ('clean');
  ok( dies { Finance::Tiller2QIF::run_cli() }, 'clean without --db dies' );
};

subtest cli_clean => sub {
  my $dbfile = uniqfile( 'cli_clean', 'sqlite3' );
  freshdb($dbfile)->disconnect;

  # Create two checkpoint copies directly, with distinct names
  Finance::Tiller2QIF::_checkpoint( $dbfile );
  sleep 1;
  Finance::Tiller2QIF::_checkpoint( $dbfile );

  my @before = grep { $_ ne $dbfile } glob( $dbfile . '*' );
  ok( @before == 2, 'two checkpoint copies exist before clean' );

  local @ARGV = ( 'clean', '--db', $dbfile );
  ok( lives { Finance::Tiller2QIF::run_cli() }, 'clean returns normally' );

  my @after = grep { $_ ne $dbfile } glob( $dbfile . '*' );
  ok( @after == 0, 'clean removed all checkpoint copies' );
  ok( -e $dbfile,  'clean left the original database intact' );
};

done_testing();

unlink glob "t/tmp/t2q_*" if test_pass();
