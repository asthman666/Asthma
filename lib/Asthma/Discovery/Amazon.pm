package Asthma::Discovery::Amazon;
use Moose;
extends 'Asthma::Discovery';

use Coro;
use AnyEvent::HTTP;
use HTTP::Headers;
use HTTP::Message;
use Asthma::Debug;
use HTML::TreeBuilder;
use Digest::MD5 qw(md5_base64);
use Data::Dumper;

sub BUILD {
    my $self = shift;
    $self->site_id(100);
}

sub run {
    my $self = shift;

    $self->start_find_urls;

    my $run = 1;
    my $start = 0;
    while ( $run ) {
        last unless $start = $self->find_urls($start);
    }
}

sub start_find_urls {
    my $self = shift;

    my $leaf_browse_ids = [$self->storage->mysql->resultset('SiteBrowse')->search({site_id => $self->site_id, is_leaf => 'y'})];
    foreach my $leaf_browse_id ( @$leaf_browse_ids ) {
        my $url = "http://www.amazon.cn/s/?node=" . $leaf_browse_id->browse_id;
        my $md5_link = md5_base64($url);
        my $now = "now()";

        my $u = $self->storage->mysql->resultset($self->site_id . 'ListUrl')->find_or_new({ link => $url,
                                                                                            md5_link => $md5_link,
                                                                                            dt_created => \$now,
                                                                                            dt_updated => \$now,
                                                                                          }, {key => 'md5_link'});
        if ( ! $u->in_storage ) {
            debug("url $url with md5 $md5_link need to be added");
            $u->insert;
        } else {
            debug("url $url with md5 $md5_link and list_url_id " . $u->list_url_id . " exists");
        }
    }
}


sub find_urls {
    my ($self, $start) = @_;

    my $rows = 100;
    my $urls = [$self->storage->mysql->resultset($self->site_id . 'ListUrl')->search(
		    undef,
		    {
			offset => $start,
			rows   => $rows,
		    })];


    my $rs = $self->storage->mysql->resultset($self->site_id . 'ListUrl')->search();
    my $count = $rs->count;
    
    if ( $count < ($start+$rows) ) {
	$rows = $count - $start;
    }

    debug("start: $start, rows: $rows");

    if ( @$urls ) {
        my $sem = Coro::Semaphore->new(100);
        my @coros;

        foreach my $url_object ( @$urls ) {
	    my $url = $url_object->link;
            push @coros,
            async {
                my $guard = $sem->guard;

                http_get $url,
                headers => $self->headers,
                Coro::rouse_cb;

                my ($body, $hdr) = Coro::rouse_wait;

		debug("$hdr->{Status} $hdr->{Reason} $hdr->{URL}");

                my $header = HTTP::Headers->new('content-encoding' => 'gzip, deflate', 'content-type' => 'text/html');
                my $mess = HTTP::Message->new( $header, $body );
                
                if ( my $content = $mess->decoded_content(charset => 'gbk') ) {
                    my $tree = HTML::TreeBuilder->new_from_content($content);

		    my @skus;
		    if ( my @sku_divs = $tree->look_down('id', qr/result_\d+/) ) {
			foreach my $div ( @sku_divs ) {
			    push @skus, $div->attr('name');
			}
		    }
		    
		    foreach my $sku ( @skus ) {
			next unless $sku;
			my $item_url = "http://www.amazon.cn/dp/$sku";
                        my $md5_link = md5_base64($item_url);
                        my $now = "now()";

                        my $u = $self->storage->mysql->resultset($self->site_id . 'ItemUrl')->find_or_new({ link => $item_url,
                                                                                                            md5_link => $md5_link,
                                                                                                            dt_created => \$now,
                                                                                                            dt_updated => \$now,
                                                                                                          }, {key => 'md5_link'});
                        if ( ! $u->in_storage ) {
                            debug("url $item_url with md5 $md5_link need to be added");
                            $u->insert;
                        } else {
                            debug("url $item_url with md5 $md5_link and item_url_id " . $u->item_url_id . " exists");
                        }
		    }

		    if ( $tree->look_down('id', 'pagnNextLink') ) {
			my $page_url = $tree->look_down('id', 'pagnNextLink')->attr('href');
			$page_url = URI->new_abs($page_url, $url)->as_string;
                        my $md5_link = md5_base64($page_url);
                        my $now = "now()";

                        my $u = $self->storage->mysql->resultset($self->site_id . 'ListUrl')->find_or_new({ link => $page_url,
                                                                                                            md5_link => $md5_link,
                                                                                                            dt_created => \$now,
                                                                                                            dt_updated => \$now,
                                                                                                          }, {key => 'md5_link'});
                        if ( ! $u->in_storage ) {
                            debug("url $page_url with md5 $md5_link need to be added");
                            $u->insert;
                        } else {
                            debug("url $page_url with md5 $md5_link and list_url_id " . $u->list_url_id . " exists");
                        }
		    }
                    
		    $tree->delete;
                }
            }
        }

        $_->join foreach ( @coros );

        return $start+$rows;
    } else {
        return 0;
    }
}

__PACKAGE__->meta->make_immutable;

1;



