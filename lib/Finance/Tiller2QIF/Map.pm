package Finance::Tiller2QIF::Map;
# ABSTRACT: Apply mapping rules to categorize transactions

=head1 DESCRIPTION

Applies user-defined mapping rules to transactions in the SQLite database. Rules can filter by account, match transaction fields (category, payee, memo, date, amount), and set or suppress categories. Rules are evaluated in order; the first match wins.

=head1 FUNCTIONS

=head2 Map

  Finance::Tiller2QIF::Map::Map( $db_path, $mapfile );

Apply mapping rules from C<$mapfile> to transactions in the database. C<$mapfile> is optional; if omitted, transactions pass through unchanged. Rules are evaluated in order; the first matching rule sets the transaction's C<mapped_category> and/or C<skipped> flag.

=head1 AUTHOR

John Karr E<lt>brainbuz@cpan.orgE<gt>

=head1 LICENSE

GPL version 3 or later.

=cut

use v5.34;

use Mojo::SQLite;
use Path::Tiny;
use utf8;
use warnings FATAL => 'utf8';
use feature qw/signatures postderef/;

my %VALID_FIELDS = map { $_ => 1 } qw(category payee memo account date amount);

sub _resolve_dest ($dest) {
  return undef if $dest eq 'source';
  return ''    if $dest eq 'blank';
  return $dest;
}

sub _parse_line ($line) {
  # Slash-delimited pattern: field | /regex/ | dest
  if ( $line =~ /^([^|]+?)\s*\|\s*\/((?:[^\/]|\\.)*?)\/\s*\|\s*(.+?)$/ ) {
    return (
      scalar( $1 =~ s/^\s+|\s+$//gr ),
      $2,
      scalar( $3 =~ s/^\s+|\s+$//gr ),
    );
  }
  # Simple three-field split: no | allowed in pattern except \| for literal pipe
  my @parts = split /(?<!\\)\|/, $line;
  die "Bare alternation without slash-quoting\n"
    if @parts > 3;

  @parts = map { s/^\s+|\s+$//gr } @parts;
  my $field   = shift @parts;
  my $dest    = pop @parts;
  my $pattern = $parts[0] // '';
  return ( $field, $pattern, $dest // '' );
}

sub _parse_mapping_file ($file) {
  my @rules;
  my $default      = undef;  # undef => source
  my $default_skip = 0;

  my $lineno = 0;
  for my $line ( path($file)->lines_utf8({ chomp => 1 }) ) {
    $lineno++;
    next if $line =~ /^\s*(?:#|$)/;

    # Optional account filter: [AccountPattern] at start of line.
    # Pattern follows the same alternation rules as field patterns.
    my $acct_re = undef;
    if ( $line =~ s/^\s*\[([^\]]+)\]\s*// ) {
      my $acct_pat = $1;
      $acct_re = eval { qr/$acct_pat/i }
        or die "Invalid account filter '[$acct_pat]' at line $lineno: $@\n";
    }

    my ($field, $pattern, $dest) = _parse_line($line);
    $field = lc $field;
    $dest =~ s/\\\|/|/g if defined $dest;

    if ( $field eq 'default' ) {
      die "Account filter not valid on default line at line $lineno\n"
        if defined $acct_re;
      die "Default line missing destination at line $lineno\n"
        unless defined $dest && length $dest;
      $default_skip = ( $dest eq 'skip' ? 1 : 0 );
      $default      = ( $dest eq 'skip' ? undef : _resolve_dest($dest) );
      next;
    }

    die "Unknown field '$field' at line $lineno. Valid fields: "
      . join( ', ', sort keys %VALID_FIELDS ) . "\n"
      unless $VALID_FIELDS{$field};

    die "Missing pattern at line $lineno\n"
      unless length $pattern;

    die "Missing destination at line $lineno (use 'blank' for empty category)\n"
      unless defined $dest && length $dest;

    my $re = eval { qr/$pattern/i }
      or die "Invalid regex '$pattern' at line $lineno: $@\n";

    my $is_skip = ( $dest eq 'skip' ? 1 : 0 );
    push @rules, {
      field          => $field,
      pattern        => $re,
      destination    => ( $is_skip ? undef : _resolve_dest($dest) ),
      skip           => $is_skip,
      account_filter => $acct_re,
    };
  }

  return ( \@rules, $default, $default_skip );
}

sub Map ( $options ) {

  return unless defined $options->{mapfile};
  my $mapfile  = $options->{mapfile};
  my $db_path  = $options->{db_path};
  my $verbose  = $options->{verbose} || 0;
  my ( $rules, $default, $default_skip ) = _parse_mapping_file($mapfile);

  my $dbmojo       = Mojo::SQLite->new($db_path)->options({ sqlite_unicode => 1 })->db;
  my @transactions = $dbmojo->select( 'transactions', '*', { exported => 0 } )->hashes->@*;

  for my $tx (@transactions) {
    my $mc   = $default;
    my $skip = $default_skip;
    my $matched_rule;

    MAPRULE: for my $rule (@$rules) {
      if ( defined $rule->{account_filter} ) {
        next MAPRULE unless ( $tx->{account} // '' ) =~ $rule->{account_filter};
      }
      my $val = $tx->{ $rule->{field} };
      next MAPRULE unless defined $val;
      if ( $val =~ $rule->{pattern} ) {
        $mc   = $rule->{destination};
        $skip = $rule->{skip};
        $matched_rule = "$rule->{field} ~ /$rule->{pattern}/ => " . ($rule->{skip} ? 'skip' : ($mc // 'source'));
        last MAPRULE;
      }
    }

    if ($verbose) {
      my $result = $matched_rule // 'default';
      say "TX $tx->{id} ($tx->{payee}): $result";
    }

    $dbmojo->update( 'transactions',
      { mapped_category => $mc, skipped => $skip },
      { id => $tx->{id} } );
  }

  $dbmojo->disconnect;
}

1;
