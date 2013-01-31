#!/usr/bin/perl
use strict;
use warnings;
use FindBin qw/$Bin/;
use lib "$Bin/lib";
use Asthma::Solr;
use Asthma::Debug;

my $solr = Asthma::Solr->new();
my $day = shift || 2;
my $str = "<delete><query>dt_created:[* TO NOW-${day}DAY]</query></delete>";
debug $str;
$solr->update($str);
