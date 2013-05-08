package Asthma::Spider::Amazon;
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
    $self->site_id(100);
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

		debug("$hdr->{Status} $hdr->{Reason} $hdr->{URL}");
                
                my $header = HTTP::Headers->new('content-encoding' => 'gzip, deflate', 'content-type' => 'text/html');
                my $mess = HTTP::Message->new( $header, $body );

                if ( my $content = $mess->decoded_content() ) {
                    my $sku_tree = HTML::TreeBuilder->new_from_content($content);

                    my $item = Asthma::Item->new();

                    $item->url($url);
                    
                    if ( $url =~ m{dp/(.+)} ) {
                        my $sku = $1;
                        $item->sku($sku);
                    }

                    if ( $sku_tree->look_down('id', 'btAsinTitle') ) {
                        $item->title($sku_tree->look_down('id', 'btAsinTitle')->as_trimmed_text);
                    }

                    if ( $sku_tree->look_down('id', 'actualPriceValue') ){
                        my $price = $sku_tree->look_down('id', 'actualPriceValue')->look_down('class', 'priceLarge')->as_trimmed_text;
                        $item->price($price);
                    } elsif ( $sku_tree->look_down('class', 'availGreen') && $sku_tree->look_down('class', 'availGreen')->as_trimmed_text =~ m{可以从这些卖家购买} ) {
                        # <div id="olpDivId">
                        if ( my $div = $sku_tree->look_down("id", "olpDivId") ) {
                            if ( $div->look_down("class", "price") ) {
                                my $price = $div->look_down("class", "price")->as_trimmed_text;
                                $item->price($price);
                            }
                        }
                    }
                    
                    # <span class="availRed">目前无货，</span><br />欢迎选购其他类似产品。<br />
                    if ( $sku_tree->look_down("class", "availRed") ) {
                        my $stock = $sku_tree->look_down("class", "availRed")->as_trimmed_text;
                        if ( $stock =~ m{目前无货} || $stock =~ m{缺货登记} ) {
                            $item->available("out of stock");
                        }
                    }
                    
                    # id="original-main-image"
                    if ( $sku_tree->look_down('id', 'original-main-image') ) {
                        my $image_url = $sku_tree->look_down('id', 'original-main-image')->attr('src');
                        $item->image_url($image_url);
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







