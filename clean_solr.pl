#!/usr/bin/perl
use strict;
use warnings;
use FindBin qw/$Bin/;
use lib "$Bin/lib";
use Asthma::Solr;
use Asthma::Debug;
use Getopt::Long;

my $d;
GetOptions(
    "d|day=i" => \$d,    
) or die "error parsing opt";

my $delete_query;
if ( $d ) {
    $delete_query = "dt_created:[* TO NOW/DAY-$d" . ($d == 1 ? "DAY" : "DAYS") . "]";
} else {
    $delete_query = "dt_created:[* TO NOW/DAY]";
}

my $solr = Asthma::Solr->new();
my $str = "<delete><query>$delete_query</query></delete>";
debug $str;
$solr->update($str);

$str = "<optimize/>";
debug $str;
$solr->update($str);

