package Asthma::Debug;
use strict;
use POSIX qw(strftime);
use Exporter;
use vars qw/$VERSION @ISA @EXPORT $DEBUG_FH/;

@ISA = qw/Exporter/;
@EXPORT = qw/&debug &debug_item/;

$DEBUG_FH ||= *STDERR;
$|++;

binmode($DEBUG_FH, ":encoding(utf8)");

sub debug {
    my $msg = shift;

    my @subinfo = caller(1);

    if ( $msg ) {
        my $time = strftime("%F %T", localtime());
        my $out_str = "[$time]: $$ " . $subinfo[3] . ": $msg\n";
        print $DEBUG_FH $out_str;
    }
}

sub debug_item {
    my $item = shift;
    return unless $item;
    debug("item sku: " . ($item->sku || '') . ", item url: " . ($item->url || '') . ", item name: '" . ($item->title || '') . "', price: '" . ($item->price || '') . "'" . ", available: " . $item->available);
}

1;
