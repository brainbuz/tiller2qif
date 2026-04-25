package Finance::Tiller2QIF::WriteQIF;
use v5.32;

use Path::Tiny;
use Text::CSV;
use Mojo::SQLite;
use utf8;
use feature qw/signatures postderef/;
# use Data::Printer;

# Global variables to reduce passing between subroutines.
our @accounts = ();
our $sql      = {};
our @qif      = ();

# Initializes the global sql object and accounts list.
sub _init($db_path) {
  $sql = Mojo::SQLite->new($db_path);
  @accounts =
    map { $_->[0] }
    $sql->db->query(
    q{SELECT distinct(account) FROM transactions WHERE exported = 0;})
    ->arrays->@*;
}

sub Emit ( $db_path, $outfile ) {
  _init($db_path);
  for my $account (@accounts) {
    my $header = join( "\n", "!Account", "N$account", "^", "!Type:Bank" );
    my @tx     = $sql->db->query(
      q{ SELECT * FROM transactions
          WHERE exported = 0
          AND account = ?
          ORDER BY date, payee; },
      $account
    )->hashes()->@*;
    my @qif_tx = map {
      join( "\n",
        "D$_->{date}", "T$_->{amount}", "P$_->{payee}",
        ( $_->{memo} ? "M$_->{memo}" : () ),
        ( $_->{category} ? "L$_->{category}" : () ), "^" )
    } @tx;
    push @qif, $header, @qif_tx;
  }

 # Combine all QIF fragments into a single multi-account QIF and write to file

  path($outfile)->spew_utf8( join( "\n", @qif ) . "\n" );
}

1;
