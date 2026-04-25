package Finance::Tiller2QIF::Util;
use v5.32;

use Path::Tiny;
use Text::CSV;
use Mojo::SQLite;
use feature qw/signatures postderef/;

my $newDB = q/
CREATE TABLE IF NOT EXISTS transactions (
    id TEXT PRIMARY KEY,               -- Transaction ID from CSV
    account TEXT NOT NULL,
    date TEXT NOT NULL,                -- YYYY-MM-DD
    amount REAL NOT NULL,
    payee TEXT,
    memo TEXT,
    category TEXT,
    exported INTEGER NOT NULL DEFAULT 0
);
/;

sub InitDB ( $sqlite ){
    my $db = Mojo::SQLite->new($sqlite);
    $db->db->query($newDB) || die "unable to initialize database $!\n";
    say "Database $sqlite created";
}

my $example = q|
{
  # Uncomment and customize values for your needs
  # file format is json with comments
  # tiller2qif ignores everything after '#' on a line

  # "input": "~/Downloads/mytillerdump.csv",
  # "output": "/tmp/tillerout.qif",
  # "db": "~/.data/tiller2qif.sqlite3"
}
|;

sub InitConfig ( $opt ) {
  unless ( $opt->config ) {
    my $default= '~/.config/tiller2qif.conf';
    print "Name of Config File (default: ${default} ) ? ";
    my $r = <STDIN>;
    chomp $r;
    my $config = $r ? $r : $default;
    path( $config )->spew_utf8( $example ) || die "unable to create $config : $! \n";
    exit;
  }

}


1;
