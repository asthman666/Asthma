package Asthma::Spider::1HaoDian;
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
    $self->site_id(112);
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
                #my $header = HTTP::Headers->new('content-type' => 'text/html');
                my $mess = HTTP::Message->new( $header, $body );

                if ( my $content = $mess->decoded_content() ) {
                    my $sku_tree = HTML::TreeBuilder->new_from_content($content);

                    my $item = Asthma::Item->new();

                    if ( my $h2 = $sku_tree->look_down('id', 'productMainName') ) {
                        if ( my @titles = $h2->content_list ) {
                            $item->title($titles[0]);
                        }
                    }
                    
                    if ( $url =~ m{(?:item|product)/(\d+)} ) {
                        my $sku = $1;
                        $item->sku($sku);
                        $item->url($url);
                        $self->set_stock($item);
                    }
                    
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

sub set_stock {
    my $self = shift;
    my $item = shift;

    my $sku  = $item->sku;
    my $url  = $item->url;

    my $stock_url;

    if ( $url =~ m{1mall\.com} ) {
        $stock_url = "http://busystock.i.1mall.com/restful/detail?mcsite=1&provinceId=26&pmId=$sku";
    } else {
        $stock_url = "http://busystock.i.yihaodian.com/restful/detail?mcsite=1&provinceId=26&pmId=$sku";
    }

    debug("url:$url");
    debug("stock:$stock_url");

    my $resp = $self->ua->get($stock_url);
    if ( $resp->is_success ) {
        if ( my $stock_content = $resp->decoded_content ) {
            debug("stock content: $stock_content");

            use JSON;
            my $ref = decode_json($stock_content);

            #debug Dumper $ref;

            if ( $ref->{currentPrice} ) {
                $item->price($ref->{currentPrice});
            }

            if ( $ref->{currentStockNum} <= 0 ) {
                $item->available('out of stock');
            }
        }
    } else {
        debug("resp status_line: " . $resp->status_line);
    }
}


__PACKAGE__->meta->make_immutable;

1;





