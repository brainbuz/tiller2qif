package Finance::Tiller2QIF::Util;
# ABSTRACT: Utility functions for Tiller2QIF processing

=head1 DESCRIPTION

Provides utility functions for initializing the SQLite database and configuration files.

=head1 FUNCTIONS

=head2 InitDB

  Finance::Tiller2QIF::Util::InitDB( $db_path );

Create a new SQLite database at C<$db_path> with the transactions table schema. Dies if unable to create the database.

=head2 InitConfig

  Finance::Tiller2QIF::Util::InitConfig( $config_path );

Create a starter JSON configuration file at C<$config_path> with commented examples of all available options. Dies if unable to write the file.

=head1 AUTHOR

John Karr E<lt>brainbuz@cpan.orgE<gt>

=head1 LICENSE

GPL version 3 or later.

=cut

use v5.34;

use Path::Tiny;
use Text::CSV;
use Mojo::SQLite;
use utf8;
use warnings FATAL => 'utf8';
use open ':std', ':encoding(UTF-8)';
use feature qw/signatures postderef/;

my $newDB = q/
CREATE TABLE IF NOT EXISTS transactions (
    id TEXT PRIMARY KEY,               -- Transaction ID from CSV
    account TEXT NOT NULL,
    date TEXT NOT NULL,                -- YYYY-MM-DD
    amount REAL NOT NULL,
    payee TEXT,
    memo TEXT,
    category TEXT,                     -- source category from Tiller (immutable after ingest)
    mapped_category TEXT,              -- destination category set by Map phase; NULL = not yet mapped
    check_number TEXT,                 -- NULL when absent or zero-filled by Tiller
    skipped      INTEGER NOT NULL DEFAULT 0,  -- 1 = suppressed by map rule; excluded from QIF
    exported     INTEGER NOT NULL DEFAULT 0
);
/;

sub InitDB ( $sqlite ) {
    my $db = Mojo::SQLite->new($sqlite)->options({ sqlite_unicode => 1 });
    # uncoverable branch true
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
  # "db": "~/.data/tiller2qif.sqlite3",
  # "mapfile": "~/data/tiller2qif.mapfile"
}
|;

sub InitConfig ( $config ) {
  # devel coverage errors
  # uncoverable branch true
  # uncoverable branch false
  path( $config )->spew_utf8( $example ) || die "unable to create $config : $! \n";
}

1;
