#!/usr/bin/perl
use strict;
use warnings;
use FindBin qw/$Bin/;
use lib "$Bin/../lib";
use Getopt::Long;
use Asthma::Debug;
use Asthma::Amazon;
use Asthma::Storage;
use XML::Simple;
use Data::Dumper;
use utf8;

my $browse_id;

my %options;
GetOptions(
    "b|browse_id=i" => \$browse_id,
) or die "error parsing opt";

unless ($browse_id) {
    die <<USAGE;
perl $0 [options]
    options:
        -b, --browse_id        running module, eg: 34834
USAGE
}

my $site_id = 100;
my $now = "now()";

my $storage = Asthma::Storage->new;
my $aws = Asthma::Amazon->new;

get_browse($browse_id, "0", "根");

sub get_browse {
    my $browse_id = shift;
    my $parent_browse_tree = shift;
    my $parent_browse_tree_value = shift;
    return unless $browse_id;

    my $request = {
        Operation => 'BrowseNodeLookup',
        BrowseNodeId => $browse_id,
    };

    my $content = $aws->content($request);
    my $ref = eval{ XMLin($content)->{BrowseNodes}->{BrowseNode} };

    sleep 1;

    my @parent_browse_ids = split(/>/, $parent_browse_tree);
    my $level = @parent_browse_ids;
    my $parent_browse_id = $parent_browse_ids[-1];

    my $browse_tree = "$parent_browse_tree>$browse_id";
    my $browse_tree_value = "$parent_browse_tree_value>$ref->{Name}";

    my $is_leaf = 'n';
    unless ( $ref->{Children} ) {
        $is_leaf = 'y';
    }

    $storage->mysql->resultset('SiteBrowse')->find_or_create({ site_id => $site_id,
                                                               browse_id => $browse_id,
                                                               value => $ref->{Name},
                                                               parent_browse_id => $parent_browse_id,
                                                               browse_tree => $browse_tree,
                                                               browse_tree_value => $browse_tree_value,
                                                               level => $level,
                                                               is_leaf => $is_leaf,
                                                               dt_created => \$now,
                                                               dt_updated => \$now,
                                                             });
    return unless $ref->{Children};

    foreach my $h ( @{$ref->{Children}->{BrowseNode}} ) {
        if ( $parent_browse_id == 0 ) {
            if ( $h->{IsCategoryRoot} ) {
                get_browse($h->{BrowseNodeId}, $browse_tree, $browse_tree_value);
            }
        } else {
            get_browse($h->{BrowseNodeId}, $browse_tree, $browse_tree_value);
        }
    }
}

1;

