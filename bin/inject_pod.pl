#!/usr/bin/env perl
# Inject the contents of a .pod file at the '## POD ##' placeholder
# in one or more target files. Run by [Run::AfterBuild] in dist.ini.
# Excluded from the built distribution via [PruneFiles] in dist.ini.

use v5.34;
use strict;
use warnings;
use utf8;
use warnings FATAL => 'utf8';
use open ':std', ':encoding(UTF-8)';
use Path::Tiny;

my ($pod_file, @targets) = @ARGV;
die "Usage: $0 <pod-file> <target-file> [<target-file> ...]\n"
  unless $pod_file && @targets;

my $pod = path($pod_file)->slurp_utf8;
chomp $pod;
die "POD file '$pod_file' is empty\n" unless length $pod;

for my $target (@targets) {
  my $content = path($target)->slurp_utf8;
  unless ($content =~ s/^## POD ##$/$pod/m) {
    warn "No '## POD ##' placeholder found in $target\n";
    next;
  }
  path($target)->spew_utf8($content);
  say "Injected POD into $target";
}
