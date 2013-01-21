package Asthma::Spider::JingDongMobile;
use Moose;
extends 'Asthma::Spider';
with 'Asthma::Tool';

use utf8;
use Asthma::Item;
use Asthma::Debug;
use HTML::TreeBuilder;
use AnyEvent;
use AnyEvent::HTTP;
use HTTP::Headers;
use HTTP::Message;
use URI;
#use Data::Dumper;

has 'start_url' => (is => 'rw', isa => 'Str');

sub BUILD {
    my $self = shift;
    $self->site_id(102);
    $self->start_url('http://www.360buy.com/products/652-653-655.html');
}

sub run {
    my $self = shift;

    my $resp = $self->ua->get($self->start_url);
    
    $self->find($resp);

    my $run = 1;
    while ( $run ) {
	#debug("self urls" . Dumper $self->urls);
	if ( my $url  = shift @{$self->urls} ) {
	    my $resp = $self->ua->get($url);
	    $self->find($resp);
	} else {
	    $run = 0;
	}
    }
}

sub find {
    my $self = shift;
    my $resp = shift;
    return unless $resp;
    
    debug("process: " . $resp->request->uri->as_string);

    my @skus;

    if ( my $content = $resp->decoded_content ) {
        my $tree = HTML::TreeBuilder->new_from_content($content);
        
        # find next page
        if ( $tree->look_down('class', 'pagin pagin-m') ) {
            if ( $tree->look_down('class', 'pagin pagin-m')->look_down("class", "next") ) {
                if ( my $page_url = $tree->look_down('class', 'pagin pagin-m')->look_down("class", "next")->attr("href") ) {
                    $page_url = URI->new_abs($page_url, $resp->base)->as_string;
                    debug("get next page_url: $page_url");
                    push @{$self->urls}, $page_url;
                }
            }
        }

        # find skus
        foreach my $plist ( $tree->look_down("id", "plist") ) {
            foreach my $item ( $plist->look_down(_tag => 'li', sku => qr/\d+/) ) {
                push @skus, $item->attr("sku");
            }
        }

        $tree->delete;
    }

    if ( @skus ) {
	my $cv = AnyEvent->condvar;

	foreach my $sku ( @skus ) {
            my $url = "http://www.360buy.com/product/$sku.html";

	    $cv->begin;
	    http_get $url, 
	    headers => {
		"user-agent" => "Mozilla/5.0 (Windows NT 6.1; rv:17.0) Gecko/20100101 Firefox/17.0",
		"Accept-Encoding" => "gzip, deflate",
		'Accept-Language' => "zh-cn,zh;q=0.8,en-us;q=0.5,en;q=0.3",
		'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
	    },

	    sub {
		my ( $body, $hdr ) = @_;
		
		my $header = HTTP::Headers->new('content-encoding' => "gzip, deflate", 'content-type' => 'text/html');
		my $mess = HTTP::Message->new( $header, $body );
		my $content = $mess->decoded_content(charset => 'gb2312');
		my $item = $self->parse($content);

		$item->sku($sku);
		$item->url($url);

		debug_item($item);
		
		$self->add_item($item);
		$cv->end;
	    }
	}
	$cv->recv;
    }
}

sub parse {
    my $self    = shift;
    my $content = shift;

    my $item = Asthma::Item->new();

    if ( $content ) {
	my $sku_tree = HTML::TreeBuilder->new_from_content($content);

	if ( $sku_tree->look_down(_tag => 'h1') ) {
	    $item->title($sku_tree->look_down(_tag => 'h1')->as_trimmed_text);
	}
        
        if ( $sku_tree->look_down('id', 'product-intro') ) {
            if ( my $price_image = $sku_tree->look_down('id', 'product-intro')->look_down("class", "p-price") ) {
                if ( $price_image->look_down(_tag => "img") ) {
                    my $price_url = $price_image->look_down(_tag => "img")->attr("src");
                    if ( my $price = $self->get_price($price_url) ) {
                        $item->price($price);
                    }
                }
            }
        }

	if ( $sku_tree->look_down('id', 'spec-n1') ) {
            if ( my $img = $sku_tree->look_down('id', 'spec-n1')->look_down(_tag => 'img') ) {
                if ( my $image_url = $img->attr("src") ) {
                    $item->image_url($image_url);
                }
            }
        }
        
	$sku_tree->delete;
    }

    return $item;
}

__PACKAGE__->meta->make_immutable;

1;

