#!/usr/bin/perl
use strict;
use warnings;
use FindBin qw/$Bin/;
use lib "$Bin/lib";
use Asthma::Debug;
use File::Find::Rule;

my $file_dir = "/var/file/his";
exit 0 unless -d $file_dir;

my @files = File::Find::Rule->file()
                            ->name( '*.xml' )
                            ->in( $file_dir );

my @files_expired;

foreach my $file ( @files ) {
    my $mtime = (stat($file))[9];
    #debug("file $file, mtime: $mtime");
    push(@files_expired, $file) if $mtime + 3600*24*3 < time;
}

if ( @files_expired ) {
    my $num = unlink @files_expired;
    debug("files expired: " . join(",", @files_expired) . ", file num: " . scalar(@files_expired) . ", successed delete num: $num");
} else {
    debug("no files need to be deleted");
}





