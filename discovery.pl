#!/usr/bin/perl
use strict;
use warnings;
use FindBin qw/$Bin/;
use lib "$Bin/lib";
use Getopt::Long;
use Asthma::Debug;
use Class::Load 'load_class';

my ($m, $f, $t, $d);
$d = 0;

my %options;
GetOptions(
    "m|module=s" => \$m,
    "d|depth=i" => \$d,
) or die "error parsing opt";

unless ($m) {
    die <<USAGE;
perl $0 [options]
    options:
        -m, --module        running module, eg: 51Buy
        -d, --depath        running depth
USAGE
}

debug("use module: $m");

my $module = "Asthma::Discovery::$m";
load_class($module) or die "Failed to load $module\n";

debug("begin to run");

my $object = $module->new(depth => $d);
$object->run;

debug("run done");

1;

