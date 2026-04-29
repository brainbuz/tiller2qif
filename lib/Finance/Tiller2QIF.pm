package Finance::Tiller2QIF;
# ABSTRACT: Convert Tiller CSV exports to QIF format

use v5.34;
use strict;
use warnings;
use utf8;
use warnings FATAL => 'utf8';
use open ':std', ':encoding(UTF-8)';

use feature qw/signatures postderef try/;

use Path::Tiny;
use Getopt::Long::Descriptive;
use Cpanel::JSON::XS;
use Finance::Tiller2QIF::ReadCSV;
use Finance::Tiller2QIF::Map;
use Finance::Tiller2QIF::Util;
use Finance::Tiller2QIF::WriteQIF;
use Time::Piece;
# use Data::Printer;

=pod

=head1 NAME

Finance::Tiller2QIF

=cut

## POD ##

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

sub ingest (%options) {
  Finance::Tiller2QIF::ReadCSV::Ingest( $options{input}, $options{db},
    $options{verbose} );
}

sub apply_map (%options) {
  Finance::Tiller2QIF::Map::Map( $options{db}, $options{mapfile},
    $options{verbose} );
}

sub emit (%options) {
  Finance::Tiller2QIF::WriteQIF::Emit( $options{db}, $options{output},
    $options{verbose} );
}

sub run (%options) {
  ingest(%options);
  apply_map(%options);
  emit(%options);
}

sub _checkpoint($file) {
  my $new = "$file." . localtime()->datetime();
  $new =~ tr/\:/_/;
  path($file)->copy($new);
}

sub _clean_checkpoints($file) {
  my @checkpoints = grep { $_ ne $file } glob( $file . '*' );
  for my $cp (@checkpoints) {
    path($cp)->remove;
    say "Removed checkpoint: $cp";
  }
  return scalar @checkpoints;
}

# ---------------------------------------------------------------------------
# CLI entry point — called by bin/tiller2qif
# ---------------------------------------------------------------------------

my $VALID_COMMANDS = join '|',
  qw(run ingest map emit newdb newconfig checkconfig clean version);

my $hlpmsg = <<'END_USAGE';
tiller2qif — Convert Tiller Money CSV exports to QIF format.

Ingests a Tiller CSV into a SQLite database, optionally applies a
category-mapping file, then writes a QIF file ready for import into
GnuCash, KMyMoney, Quicken, HomeBank, and similar programs.

Usage: tiller2qif <command> %o

Commands: run | ingest | map | emit | newdb | newconfig | checkconfig | version

For the full manual: perldoc Finance::Tiller2QIF
END_USAGE

my $badcmdhelp = <<'BADCMD';

There was an error in your command line.
Common causes are:
* mistyping an option
* command after options
* accidental text in the line

BADCMD

sub run_cli {
  my $cmd = '';
  # uncoverable branch true
  # uncoverable branch false
  if ( @ARGV && $ARGV[0] !~ /^-/ ) {
    $cmd = lc shift @ARGV;
  }

  my ( $opt, $usage ) = eval {
    describe_options(
      $hlpmsg,
      [ 'config|c=s',   "JSON config file" ],
      [ 'checkpoint|C', "copy database with timestamp before run." ],
      [ 'input|i=s',    "CSV file to read      (ingest, run)" ],
      [ 'output|o=s',   "QIF file to write     (emit, run)" ],
      [ 'db|d=s', "SQLite database file  (all commands except newconfig)" ],
      [ 'mapfile|f=s', "Category mapping file (map, run — optional)" ],
      [ 'verbose|v',   "Print detailed progress information" ],
      [],
      [ 'help|h', "Print usage and exit", { shortcircuit => 1 } ],
    );
  };
  die $@, $badcmdhelp if $@;

  if ( $opt->help ) {
    say $usage;
    exit 0;
  }

  if ( !$cmd ) {
    die
"Command Missing! Valid commands: $VALID_COMMANDS\nFor help: tiller2qif --help\n";
  }

  die "Unknown command '$cmd'. Valid commands: $VALID_COMMANDS\n"
    unless $cmd =~ /^(?:$VALID_COMMANDS)$/;

  if ( $cmd eq 'version' ) {
    # uncoverable branch true
    # uncoverable branch false
    my $v = do { no strict 'vars'; $VERSION ? $VERSION : 'unversioned' };
    say "Tiller2QIF VERSION: ${v}";
    exit 0;
  }

  if ( $cmd eq 'newconfig' ) {
    die "newconfig requires --config\n" unless $opt->config;
    say "Creating config file: " . $opt->config if $opt->verbose;
    Finance::Tiller2QIF::Util::InitConfig( $opt->config );
    say "Config file created: " . $opt->config;
    return;
  }

  my %options = ();
  if ( $opt->config ) {
    my $config = Cpanel::JSON::XS->new->utf8->relaxed->decode(
      path( $opt->config )->slurp_utf8 );
    %options = %$config;
  }

  for my $key (qw( input output db verbose mapfile )) {
    my $val = $opt->$key();
    $options{$key} = $val if defined $val;
  }

  if ( $cmd eq 'newdb' ) {
    die "newdb requires --db\n" unless $options{db};
    say "Creating database: " . $options{db} if $opt->verbose;
    Finance::Tiller2QIF::Util::InitDB( $options{db} );
    say "Database initialized: " . $options{db};
    return;
  }

  if ( $cmd eq 'clean' ) {
    die "clean requires --db\n" unless $options{db};
    my $removed = _clean_checkpoints( $options{db} );
    say "Removed $removed checkpoint(s)";
    return;
  }

  my @missing;
  push @missing, '--input'  if $cmd =~ /^(?:ingest|run)$/ && !$options{input};
  push @missing, '--db'     if !$options{db};
  push @missing, '--output' if $cmd =~ /^(?:emit|run)$/ && !$options{output};

  if (@missing) {
    die "tiller2qif $cmd: missing required option(s): "
      . join( ', ', @missing ) . "\n";
  }

  if ( $opt->verbose || $cmd eq 'checkconfig' ) {
    Finance::Tiller2QIF::Util::CheckConfig(%options);
  }

  if ( $opt->checkpoint || $cmd eq 'run' ) {
    _checkpoint( $options{db} );
  }

  if ( $cmd =~ /^(?:ingest|run)$/ ) {
    say "Ingesting CSV: " . $options{input} if $opt->verbose;
    my $newitems = ingest(%options);
    say "Ingested: ${newitems} transactions from: " . $options{input};
  }

  if ( $cmd =~ /^(?:map|run)$/ ) {
    if ( $options{mapfile} ) {
      say "Applying mapping: " . $options{mapfile} if $opt->verbose;
      apply_map(%options);
      say "Mapping applied: " . $options{mapfile};
    }
    else {
      say "No mapfile provided, skipping mapping phase";
    }
  }

  if ( $cmd =~ /^(?:emit|run)$/ ) {
    say "Writing QIF: " . $options{output} if $opt->verbose;
    my $changed = emit(%options);
    say "QIF written: ${\ $options{output}}, ${changed} records emitted!";
  }
}

1;
