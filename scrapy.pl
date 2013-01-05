#!/usr/bin/perl

use strict;
use warnings;
use FindBin qw/$Bin/;
use lib "$Bin/lib";
use Getopt::Long;
use Asthma::Debug;
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

debug("use module: $m");

my $module = "Asthma::Spider::$m";
load_class($module) or die "Failed to load $module\n";

debug("begin to run");

my $object = $module->new();
$object->run;

if ( $object->{items} ) {
    $object->wf;
}

debug("run done");

1;
