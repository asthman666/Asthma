package Asthma::Spider::1HaoDianMobile;
use Moose;
extends 'Asthma::Spider';

use utf8;
use Asthma::Item;
use Asthma::Debug;
use HTML::TreeBuilder;
use Data::Dumper;
use JSON;

sub BUILD {
    my $self = shift;
    $self->site_id(112);
    $self->start_url('http://www.yihaodian.com/ctg/searchPage/c23586-%E6%89%8B%E6%9C%BA/b/a-s1-v0-p_PAGE_-price-d0-f0-m1-rt0-pid-k');
}

sub run {
    my $self = shift;

    my $start_url = $self->start_url;

    foreach ( 1..34 ) {
        my $url = $start_url;
        $url =~ s{_PAGE_}{$_}; 
        my $resp = $self->ua->get($url);        
        $self->find($resp);
    }
}

sub find {
    my $self = shift;
    my $resp = shift;
    return unless $resp;
    
    debug("process: " . $resp->request->uri->as_string);

    my $content = $resp->decoded_content;

    while ( $content =~ m{<li\s+class=\\"producteg\\"\s+id=\\"producteg_(.+?)\\">(.+?)<\\/li>}isg ) {
        my $item = Asthma::Item->new;

	if ( my $chunk = $2 ) {
            if ( $chunk =~ m{title=\\"(.+?)\\"}is ) {
                my $title = $1;
                $item->title($title);
            }

            if ( $chunk =~ m{<strong.+?>(.+?)<\\/strong>} ) {
                my $price = $1;
                $item->price($price);
            }

            if ( $chunk =~ m{href=\\"(.+?)\\"} ) {
                my $url = $1;
                if ( $url =~ m{(?:item|product)/(\d+)} ) {
                    my $sku = $1;
                    $item->sku($sku);
                    $item->url($url);
                }
            }
	}

        if ( my $ava = $self->get_stock($1) ) {
            $item->available($ava);
        }

        debug_item($item);

        $self->add_item($item);
    }
}

sub get_stock {
    my $self       = shift;
    my $product_id = shift;

    my $url = "http://busystock.i.yihaodian.com/busystock/restful/truestock?mcsite=1&provinceId=26&productIds=$product_id";
    my $resp = $self->ua->get($url);
    my $stock_content = $resp->content;
    
    my $ref = decode_json($stock_content);
    if ( $ref->[0]->{productStock} <= 0 ) {
        return 'out of stock';
    }

    return;
}


__PACKAGE__->meta->make_immutable;

1;



