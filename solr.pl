#!/usr/bin/perl
use strict;
use warnings;
use FindBin qw/$Bin/;
use lib "$Bin/lib";
use Asthma::Solr;
use Asthma::Debug;

my $file_dir = "file";
exit 0 unless -d $file_dir;

opendir(my $dh, $file_dir);
my @files = grep {$_ !~ /^\./ && -f "$file_dir/$_" && $_ ne "README" } readdir($dh);
closedir $dh;

my $solr = Asthma::Solr->new();

foreach my $file ( @files ) {
    $file = $file_dir . "/" . $file;
}

@files = sort {(stat($a))[9] <=> (stat($b))[9]} @files;

foreach my $file ( @files ) {
    debug("file $file will be posted to solr");
    open my $fh, "<", $file;
    my $str = do {local $/; <$fh>};
    close $fh;
    $solr->update($str);
}
