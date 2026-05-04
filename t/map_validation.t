use strict;
use warnings;
use utf8;
use warnings FATAL => 'utf8';
use open ':std', ':encoding(UTF-8)';
use Test2::V0;
use Test2::Bundle::More;
use Test2::Tools::Exception qw/dies/;
use Path::Tiny;
use Finance::Tiller2QIF::Map;
use Finance::Tiller2QIF::Util;
use Mojo::SQLite;
use feature qw/signatures postderef/;

require './t/TestHelper.pm';

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

done_testing();
unlink glob "t/tmp/t2q_*" if test_pass();
