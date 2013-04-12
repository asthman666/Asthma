package Asthma::Spider::JD;
use Moose;
extends 'Asthma::Spider';

use utf8;
use Asthma::Item;
use Asthma::Debug;
use HTML::TreeBuilder;
use URI;
use Coro;
use Coro::Semaphore;
use AnyEvent;
use AnyEvent::HTTP;
use HTTP::Headers;
use HTTP::Message;

sub BUILD {
    my $self = shift;
    $self->site_id(102);
}

sub run {
    my $self = shift;

    my $loop = 0;
    my $run = 1;
    while ( $run ) {
        last unless $self->parse_item_urls($loop++);
    }
}

sub parse_item_urls {
    my ($self, $loop) = @_;
    my $start = 100*$loop;
    my $end   = $start+99;

    debug("start: $start, end: $end");

    my $urls = $self->storage->redis_db->execute('ZRANGE', $self->item_url_link, $start, $end);

    if ( @$urls ) {
        # parse
        my @items = $self->parse($urls);
        
        # set price
        $self->set_price(@items);

        # set stock
        $self->set_stock(@items);

        foreach my $item ( @items ) {
            debug_item($item);
            #$self->add_item($item);
        }

        return 1;
    } else {
        return 0;
    }    

}

sub parse {
    my $self = shift;
    my $urls = shift;

    my @items;

    my $sem = Coro::Semaphore->new(30);
    my @coros;

    foreach my $url ( @$urls ) {
        push @coros,
        async {
            my $guard = $sem->guard;

            http_get $url,
            headers => $self->headers,
            Coro::rouse_cb;

            my ($body, $hdr) = Coro::rouse_wait;
            debug("$hdr->{Status} $hdr->{Reason} $hdr->{URL}");
            
            if ( $url =~ m{item\.jd.com/(\d+)\.html} ) {
                my $sku = $1;

                my $item = Asthma::Item->new();
                $item->sku($sku);
                $item->url($url);
                
                # extract info from html content
                my $header = HTTP::Headers->new('content-encoding' => "gzip, deflate", 'content-type' => 'text/html');
                my $mess = HTTP::Message->new( $header, $body );
                if ( my $content = $mess->decoded_content(charset => 'gbk') ) {
                    my $sku_tree = HTML::TreeBuilder->new_from_content($content);

                    if ( $sku_tree->look_down(_tag => 'h1') ) {
                        $item->title($sku_tree->look_down(_tag => 'h1')->as_trimmed_text);
                    }

                    # <div id="product-intro" >
                    if ( my $div = $sku_tree->look_down('id', 'product-intro') ) {
                        if ( my $h3 = $div->look_down(_tag => 'h3')	 ) {
                            if ( $h3->as_trimmed_text =~ m{该商品已下柜} ) {
                                $item->available('out of stock');
                            } 
                        }
                    }

                    if ( $content =~ m{skuidkey\s*:\s*'(.+?)'} ) {
                        $item->extra->{skuidkey} = $1;
                    }
                    $sku_tree->delete;
                }
                
                push @items, $item;
            }
        }
    }
    
    $_->join foreach ( @coros );

    return @items;
}

sub set_price {
    my $self  = shift;
    my @items = @_;
    
    my $sem = Coro::Semaphore->new(30);

    my @coros;
    foreach my $item ( @items ) {
	my $price_url = "http://jprice.360buy.com/price/np" . $item->sku . "-TRANSACTION-J.html";
	push @coros,
	async {
	    my $guard = $sem->guard;

	    http_get $price_url,
	    headers => $self->headers,
	    Coro::rouse_cb;

	    my ($body, $hdr) = Coro::rouse_wait;
	    debug("$hdr->{Status} $hdr->{Reason} $hdr->{URL}");

	    my $header = HTTP::Headers->new('content-encoding' => "gzip, deflate", 'content-type' => 'text/html');
	    my $mess = HTTP::Message->new( $header, $body );
	    my $content = $mess->decoded_content(charset => 'gbk');

	    if ( $content =~ m/"jdPrice":\{.*?"amount"\s*:(.*?),/is ) {
		my $price = $1;
		$item->price($price);
	    } else {
		debug("ERROR: $hdr->{URL}, body: $body, content $content");
	    }
	};
    }

    $_->join foreach ( @coros );        
}

sub set_stock {
    my $self  = shift;
    my @items = @_;

    my $sem = Coro::Semaphore->new(30);

    my @coros;
    foreach my $item ( @items ) {
	if ($item->available eq 'out of stock') {
	    debug_item($item);
	    $self->add_item($item);
	    next;
	}
	my $stock_url = "http://price.360buy.com/stocksoa/StockHandler.ashx?callback=getProvinceStockCallback&type=ststock&skuid=" . $item->extra->{skuidkey} . "&provinceid=1&cityid=72&areaid=4137";

	push @coros,
	async {
	    my $guard = $sem->guard;

	    http_get $stock_url,
	    headers => $self->headers,
	    Coro::rouse_cb;

	    my ($body, $hdr) = Coro::rouse_wait;
	    debug("$hdr->{Status} $hdr->{Reason} $hdr->{URL}");

	    if ( $body =~ m{"S":"\d+-(\d+)} ) {
		my $s = $1;
		if ( grep { $s == $_ } (18,34,0) ) {
		    $item->available('out of stock');
		}
	    }	    
	};
    }

    $_->join foreach ( @coros );        
}

__PACKAGE__->meta->make_immutable;

1;



