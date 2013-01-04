#!/usr/bin/perl

use strict;
use warnings;
use FindBin qw/$Bin/;
use lib "$Bin/lib";
use Getopt::Long;
use Class::Load 'load_class';

my ($m, $f, $t);

my %options;
GetOptions(
    "m|module=s" => \$m,
    "f|file=s" => \$f,
    "t|type=s" => \$t,
) or die "error parsing opt";

unless ($m) {
    die <<USAGE;
perl $0 [options]
    options:
        -m, --module        running module, eg: Zol
        -f, --file          data output file, eg: results.json
        -t, --type          data format, eg: json (default json)
USAGE
}

print "use module: $m\n";

my $module = "Asthma::Spider::$m";
load_class($module) or die "Failed to load $module\n";

print "begin to run\n";

$module->new()->run;

1;
