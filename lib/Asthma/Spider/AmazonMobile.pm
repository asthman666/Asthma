package Asthma::Spider::AmazonMobile;

use Moose;
extends 'Asthma::Spider';

use utf8;
use Asthma::Item;
use HTML::TreeBuilder;
use URI;
use Asthma::Debug;
use AnyEvent;
use AnyEvent::HTTP;
use HTTP::Headers;
use HTTP::Message;

# NOTE: before version 5.00 of HTML::Element, you had to call delete when you were finished with the tree, or your program would leak memory.

{
    $AnyEvent::HTTP::MAX_PER_HOST = 10;
}

sub BUILD {
    my $self = shift;
    $self->site_id(100);
    $self->start_urls(['http://www.amazon.cn/b?node=665002051', 'http://www.amazon.cn/b/?node=888483051', 'http://www.amazon.cn/b/?node=888578051', 'http://www.amazon.cn/b/?node=148770071']);
}

sub run {
    my $self = shift;

    foreach my $start_url ( @{$self->start_urls} ) {
       my $resp = $self->ua->get($start_url);
       $self->find($resp);
    }

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

    my $content = $resp->decoded_content;

    my $tree = HTML::TreeBuilder->new_from_content($content);
    
    debug("process: " . $resp->request->uri->as_string);

    if ( $tree->look_down('id', 'pagnNextLink') ) {
	my $page_url = $tree->look_down('id', 'pagnNextLink')->attr('href');
	$page_url = URI->new_abs($page_url, $resp->base)->as_string;
	debug("get next page_url: $page_url");
	push @{$self->urls}, $page_url;
    }

    my @skus;
    if ( my @sku_divs = $tree->look_down('id', qr/result_\d+/) ) {
	foreach my $div ( @sku_divs ) {
	    push @skus, $div->attr('name');
	}
    }
    
    $tree->delete;

    my $cv = AnyEvent->condvar;

    foreach my $sku ( @skus ) {
        my $url = "http://www.amazon.cn/dp/$sku";
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
	    my $content = $mess->decoded_content;
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

sub parse {
    my $self    = shift;
    my $content = shift;

    my $item = Asthma::Item->new();

    if ( $content ) {
	my $sku_tree = HTML::TreeBuilder->new_from_content($content);

	if ( $sku_tree->look_down('id', 'btAsinTitle') ) {
	    $item->title($sku_tree->look_down('id', 'btAsinTitle')->as_trimmed_text);
	}

	if ( $content =~ m{<li><b>条形码:</b>(.*?)</li>} ) {
	    my $ean = $1;
	    $item->ean($ean);
	}
	
	# <span class="availRed">目前无货，</span><br />欢迎选购其他类似产品。<br />
	if ( $sku_tree->look_down("class", "availRed") ) {
	    my $stock = $sku_tree->look_down("class", "availRed")->as_trimmed_text;
	    if ( $stock =~ m{目前无货} ) {
		$item->available("out of stock");
	    }
	}
	
	# <span id="actualPriceValue"><b class="priceLarge">￥ 29.70</b></span>
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
	
	# id="original-main-image"
	if ( $sku_tree->look_down('id', 'original-main-image') ) {
	    my $image_url = $sku_tree->look_down('id', 'original-main-image')->attr('src');
	    $item->image_url($image_url);
	}

	$sku_tree->delete;
    }

    return $item;
}


__PACKAGE__->meta->make_immutable;

1;


