package Asthma::Spider::JingDongMobile;
use Moose;
extends 'Asthma::Spider';

use utf8;
use Asthma::Item;
use Asthma::Debug;
use HTML::TreeBuilder;
use URI;
use AnyEvent;
use AnyEvent::HTTP;
use HTTP::Headers;
use HTTP::Message;

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

    if ( my $content = $resp->decoded_content )  {
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

	my @skus;
        if ( my $plist = $tree->look_down('id', 'plist') ) {
            if ( my @lis = $plist->look_down(_tag => 'li', sku => qr/\d+/) ) {
		foreach ( @lis ) {
		    my $sku = $_->attr("sku");
		    push @skus, $sku;
		}
	    }
        }

	#use Data::Dumper;debug("get sku num: " . scalar(@skus) . ", " . Dumper \@skus);

        $tree->delete;

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
		    my $item = $self->parse($content, $sku);
		    $item->url($url);

		    debug_item($item);
		    
		    $self->add_item($item);
		    $cv->end;
		}
	    }

	    $cv->recv;
	}
    }
}

sub parse {
    my $self    = shift;
    my $content = shift;
    my $sku     = shift;

    my $item = Asthma::Item->new();
    $item->sku($sku);
    
    if ( $content ) {
	my $sku_tree = HTML::TreeBuilder->new_from_content($content);

	if ( $sku_tree->look_down(_tag => 'h1') ) {
	    $item->title($sku_tree->look_down(_tag => 'h1')->as_trimmed_text);
	}

	if ( my $price = $self->fprice($sku) ) {
	    $item->price($price);
	}

	if ( $content =~ m{skuidkey\s*:\s*'(.+?)'} ) {
	    my $skuidkey = $1;
	    if ( my $ava = $self->get_stock($1) ) {
		$item->available($ava);
	    }
	}

	$sku_tree->delete;
    }

    return $item;
}

sub fprice {
    my $self = shift;
    my $sku  = shift;
    return unless $sku;
    my $price_url = "http://jprice.360buy.com/price/np" . $sku . "-TRANSACTION-J.html";

    my $pres = $self->ua->get($price_url);
    my $pcon = $pres->decoded_content;
    
    if ( $pcon =~ m/"jdPrice":\{.*?"amount"\s*:(.*?),/is ) {
        return $1;
    }

    return;
}

sub get_stock {
    my $self     = shift;
    my $skuidkey = shift;
    return unless $skuidkey;
    my $url = "http://price.360buy.com/stocksoa/StockHandler.ashx?callback=getProvinceStockCallback&type=ststock&skuid=$skuidkey&provinceid=1&cityid=72&areaid=4137";
    my $resp = $self->ua->get($url);
    my $content = $resp->decoded_content;

    if ( $content =~ m{"S":"\d+-(\d+)} ) {
	my $s = $1;
	if ( grep { $s == $_ } (18,34,0) ) {
	    return 'out of stock';
	}
    }
    
    return;
}

__PACKAGE__->meta->make_immutable;

1;


