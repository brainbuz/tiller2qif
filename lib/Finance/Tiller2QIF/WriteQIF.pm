package Finance::Tiller2QIF::WriteQIF;
# ABSTRACT: Write transactions to QIF format

=head1 DESCRIPTION

Exports transactions from the SQLite database to QIF (Quicken Interchange Format) for import into financial software. Transactions are grouped by account and sorted by date. Skipped transactions and those without effective categories are handled appropriately.

=head1 FUNCTIONS

=head2 Emit

  Finance::Tiller2QIF::WriteQIF::Emit( $db_path, $outfile );

Write all unexported, non-skipped transactions from the database to a QIF file. Each account is written as a separate QIF account block with transactions sorted by date then payee. Marks written transactions as exported in the database.

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
# use Data::Printer;

# Global variables to reduce passing between subroutines.
our @accounts = ();
our $sql      = {};
our @qif      = ();

# Initializes the global sql object and accounts list.
sub _init($db_path) {
  $sql      = Mojo::SQLite->new($db_path)->options({ sqlite_unicode => 1 });
  @qif      = ();
  @accounts =
    map { $_->[0] }
    $sql->db->query(
    q{SELECT distinct(account) FROM transactions WHERE exported = 0 AND skipped = 0;})
    ->arrays->@*;
}

sub Emit ( $db_path, $outfile, $verbose=0 ) {
  _init($db_path);
  for my $account (@accounts) {
    my $header = join( "\n", "!Account", "N$account", "^", "!Type:Bank" );
    my @tx     = $sql->db->query(
      q{ SELECT *,
              COALESCE(mapped_category, category) AS effective_category
          FROM transactions
          WHERE exported = 0
          AND skipped = 0
          AND account = ?
          ORDER BY date, payee; },
      $account
    )->hashes()->@*;
    my @qif_tx = map {
      join( "\n",
        "D$_->{date}", sprintf("T%.2f", $_->{amount}),
        ( $_->{check_number} ? "N$_->{check_number}" : () ),
        "P$_->{payee}",
        ( $_->{memo} ? "M$_->{memo}" : () ),
        ( $_->{effective_category} ? "L$_->{effective_category}" : () ), "^" )
    } @tx;
    push @qif, $header, @qif_tx;
  }

 # Combine all QIF fragments into a single multi-account QIF and write to file

  path($outfile)->spew_utf8( join( "\n", @qif ) . "\n" );

  $sql->db->query('UPDATE transactions SET exported = 1 WHERE exported = 0')->rows;
}

sub Preview ( $db_path, $verbose=0 ) {
  _init($db_path);

  my @rows;
  my %w = ( account => 7, date => 4, amount => 6, payee => 5,
            category => 8, memo => 4 );

  for my $account (@accounts) {
    my @tx = $sql->db->query(
      q{ SELECT *,
              COALESCE(mapped_category, category) AS effective_category
          FROM transactions
          WHERE exported = 0
          AND skipped = 0
          AND account = ?
          ORDER BY date, payee; },
      $account
    )->hashes()->@*;

    for my $tx (@tx) {
      my $row = {
        account  => $account,
        date     => $tx->{date}               // '',
        amount   => sprintf( "%.2f", $tx->{amount} ),
        payee    => $tx->{payee}              // '',
        category => $tx->{effective_category} // '',
        memo     => $tx->{memo}               // '',
      };
      for my $col ( keys %w ) {
        my $len = length( $row->{$col} );
        $w{$col} = $len if $len > $w{$col};
      }
      push @rows, $row;
    }
  }

  my $fmt = "%-*s  %-*s  %*s  %-*s  %-*s  %-*s\n";
  printf $fmt,
    $w{account},  'Account',
    $w{date},     'Date',
    $w{amount},   'Amount',
    $w{payee},    'Payee',
    $w{category}, 'Category',
    $w{memo},     'Memo';
  say join( '  ',
    '-' x $w{account}, '-' x $w{date},   '-' x $w{amount},
    '-' x $w{payee},   '-' x $w{category}, '-' x $w{memo} );

  for my $row (@rows) {
    printf $fmt,
      $w{account},  $row->{account},
      $w{date},     $row->{date},
      $w{amount},   $row->{amount},
      $w{payee},    $row->{payee},
      $w{category}, $row->{category},
      $w{memo},     $row->{memo};
  }

  return scalar @rows;
}

1;
