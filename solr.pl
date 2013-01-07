#!/usr/bin/perl
use strict;
use warnings;
use FindBin qw/$Bin/;
use lib "$Bin/lib";
use Asthma::Solr;

my $file = shift;
exit 0 unless $file;

my $solr = Asthma::Solr->new();
open my $fh, "<", $file;
my $str = do {local $/; <$fh>};
close $fh;
$solr->update($str);
