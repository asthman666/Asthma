#!/usr/bin/perl
use strict;
use warnings;
use FindBin qw/$Bin/;
use lib "$Bin/lib";
use Asthma::Solr;
use Asthma::Debug;
use File::Copy;
use File::Basename;

my $file_dir = "/var/file";
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
    sleep 2;
    open my $fh, "<", $file;
    my $str = do {local $/; <$fh>};
    close $fh;
    my $ret = $solr->update($str);

    my $base_name = basename($file);

    if ( $ret ) {
	move($file, "/var/file/bad/$base_name");
    } else {
	move($file, "/var/file/his/$base_name");
    }
}
