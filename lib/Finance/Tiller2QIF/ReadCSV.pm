package Finance::Tiller2QIF::ReadCSV;
use v5.32;

use Path::Tiny;
use Text::CSV;
use DBI;
use feature qw/signatures postderef/;
use DateTime::Format::Flexible;

# Enable experimental try/catch for Perl 5.32, suppressing warnings
no warnings 'experimental::try';
use feature 'try';

sub _prepare_upsert ($dbh) {
  $dbh->prepare(
    q{
    INSERT INTO transactions (id, account, date, amount, payee, memo, category)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
        account = excluded.account,
        date    = excluded.date,
        amount  = excluded.amount,
        payee   = excluded.payee,
        memo    = excluded.memo,
        category = excluded.category
    }
  );
}

sub Ingest ( $csv_file, $db_path ) {

  my $dbh = DBI->connect(
    "dbi:SQLite:dbname=$db_path",
    "", "",
    {
      RaiseError => 1,
      AutoCommit => 1,
    }
  );
  my $csv = Text::CSV->new();
  my $fh  = path($csv_file)->openr_utf8 or die "File not found: $csv_file\n";
  my $header = $csv->getline($fh)
    or die "CSV appears empty or unreadable\n";
  my @columns = @$header;

  # say "Columns detected:";
  # say "  $_" for @columns;

  # say "\nRows:";

  my $upsert = _prepare_upsert($dbh);

  while ( my $row = $csv->getline($fh) ) {
    my %r;
    @r{@columns} = @$row;
    # Normalize amount
    my $amount = $r{'Amount'} // '';
    $amount =~ s/[\$,]//g;
    # Normalize date using DateTime::Format::Flexible
    my $date = $r{'Date'} // '';
    my $dt;
    try {
      $dt = DateTime::Format::Flexible->parse_datetime($date);
      $date = $dt->ymd;
    } catch ($e) {
      warn "[WARN] Could not parse date '$date' for record: " . join(", ", map { $_ // '' } @r{@columns}) . "\n";
      next;
    }
    my $id      = $r{'Transaction ID'}   || next;
    my $account = $r{'Account'}          || '';
    my $payee   = $r{'Description'}      || $r{'Full Description'} // '';
    my $memo    = $r{'Full Description'} || '';
    my $cat     = $r{'Category'}         || '';

    # say "DB INSERT: id=[$id], account=[$account], date=[$date], amount=[$amount], payee=[$payee], memo=[$memo], cat=[$cat]";
    $upsert->execute( $id, $account, $date, $amount, $payee, $memo, $cat );
  }

}

1;
