package Asthma::Spider::Amazon;

use Moose;
extends 'Asthma::Spider';

use utf8;
use Asthma::LinkExtractor;
use Asthma::Item;
use HTML::TreeBuilder;
use URI;
use Asthma::Debug;

# NOTE: before version 5.00 of HTML::Element, you had to call delete when you were finished with the tree, or your program would leak memory.

has 'start_url' => (is => 'rw', isa => 'Str');
has 'link_extractor' => (is => 'rw', lazy_build => 1);

sub _build_link_extractor {
    my $self = shift;
    return Asthma::LinkExtractor->new();
}

sub BUILD {
    my $self = shift;
    $self->site_id(100);
    $self->start_url('http://www.amazon.cn/s?rh=n%3A658390051');
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

    my $content = $resp->decoded_content;

    my @skus;
    my $tree = HTML::TreeBuilder->new_from_content($content);
    if ( my @sku_divs = $tree->look_down('id', qr/result_\d+/) ) {
	foreach my $div ( @sku_divs ) {
	    push @skus, $div->attr('name');
	}
    }

    if ( $tree->look_down('id', 'pagnNextLink') ) {
	my $page_url = $tree->look_down('id', 'pagnNextLink')->attr('href');
	$page_url = URI->new_abs($page_url, $resp->base)->as_string;
	debug("get next page_url: $page_url");
	push @{$self->urls}, $page_url;
    }

    $tree->delete;

    foreach my $sku ( @skus ) {
        my $url = "http://www.amazon.cn/dp/$sku";
	my $resp = $self->ua->get($url);

	my $content = $resp->decoded_content;
	my $sku_tree = HTML::TreeBuilder->new_from_content($content);

	my $item = Asthma::Item->new();

	$item->sku($sku);

	if ( $sku_tree->look_down('id', 'btAsinTitle') ) {
	    $item->title($sku_tree->look_down('id', 'btAsinTitle')->as_trimmed_text);
	}

	if ( $content =~ m{<li><b>条形码:</b>(.*?)</li>} ) {
	    my $ean = $1;
	    $item->ean($ean);
	}
	
	# <span id="actualPriceValue"><b class="priceLarge">￥ 29.70</b></span>
	if ( $sku_tree->look_down('id', 'actualPriceValue') ){
	    my $price = $sku_tree->look_down('id', 'actualPriceValue')->look_down('class', 'priceLarge')->as_trimmed_text;
	    $item->price($price);
	}
	
	# id="original-main-image"
	if ( $sku_tree->look_down('id', 'original-main-image') ) {
	    my $image_url = $sku_tree->look_down('id', 'original-main-image')->attr('src');
	    $item->image_url($image_url);
	}

	$sku_tree->delete;
	
	binmode(STDOUT, ":encoding(utf8)");
	debug("item name: '" . ($item->title || '') . "', ean: '" . ($item->ean || '') . "', price: '" . ($item->price || '') . "', image_url: '" . ($item->image_url || ''));

        $self->add_item($item);
    }
}


__PACKAGE__->meta->make_immutable;

1;

