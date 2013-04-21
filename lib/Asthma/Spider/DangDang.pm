package Asthma::Spider::DangDang;
use Moose;
extends 'Asthma::Spider';

use utf8;
use Asthma::Item;
use Asthma::Debug;
use Data::Dumper;
use Coro;
use AnyEvent::HTTP;
use HTTP::Headers;
use HTTP::Message;
use HTML::TreeBuilder;

sub BUILD {
    my $self = shift;
    $self->site_id(101);
}

sub run {
    my $self = shift;

    my $page = 1;
    my $run = 1;
    while ( $run ) {
        last unless $self->parse_item_urls($page++);
    }
}

sub parse_item_urls {
    my ($self, $page) = @_;
    my $rows = 100;
    debug("page: $page, rows: $rows");

    my $urls = [$self->storage->mysql->resultset($self->site_id . 'ItemUrl')->search(
		    undef,
		    {
			page => $page,
			rows => $rows,
		    })];

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
                
                my $header = HTTP::Headers->new('content-encoding' => 'gzip, deflate', 'content-type' => 'text/html');
                my $mess = HTTP::Message->new( $header, $body );

                if ( my $content = $mess->decoded_content() ) {
                    my $sku_tree = HTML::TreeBuilder->new_from_content($content);

                    my $item = Asthma::Item->new();
                    if ( my $h1 = $sku_tree->look_down(_tag => 'h1') ) {
                        if ( my @titles = $h1->content_list ) {
                            $item->title($titles[0]);
                        }
                    }

                    if ( $url =~ m{product\.aspx\?product_id=(\d+)} ) {
                        my $sku = $1;
                        $item->sku($sku);
                        $item->url($url);
                    }

                    if ( my $i = $sku_tree->look_down('id', 'promo_price') ) {
                        if ( my $price = $i->as_trimmed_text ) {
                            $price = (split(/-/, $price))[0];
                            $item->price($price);
                        }
                    } elsif ( my $span = $sku_tree->look_down('id', 'salePriceTag') ) {
                        if ( my $price = $span->as_trimmed_text ) {
                            $item->price($price);
                        }
                    }

                    if ( $content =~ m{暂时缺货} ) {
                        $item->available('out of stock');
                    }
                    
                    $sku_tree->delete;
                    
                    debug_item($item);
                    $self->add_item($item);
                }
            }
        }

        $_->join foreach ( @coros );

        return 1;
    } else {
        return 0;
    }    

}

__PACKAGE__->meta->make_immutable;

1;






