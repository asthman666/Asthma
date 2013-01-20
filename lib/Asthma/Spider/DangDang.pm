package Asthma::Spider::DangDang;

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
    $self->site_id(101);
    $self->start_url('http://searchb.dangdang.com/?category_path=01.00.00.00.00.00');
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

    my @urls;
    my $tree = HTML::TreeBuilder->new_from_content($content);

    # <div class="listitem detail">
    # <li class="maintitle" name="Name"> 
    if ( my @divs = $tree->look_down('class', 'listitem detail') ) {
	foreach my $div ( @divs ) {
	    if ( my $name_chunk = $div->look_down(class => 'maintitle', name => 'Name') ) {
		if ($name_chunk->look_down(_tag => 'a')) {
		    push @urls, $name_chunk->look_down(_tag => 'a')->attr('href');
		}
	    }
	}
    }

    if ( $tree->look_down(class => 'pagebtn', name => 'link_page_next') ) {
	my $page_url = $tree->look_down(class => 'pagebtn', name => 'link_page_next')->attr('href');
	$page_url = URI->new_abs($page_url, $resp->base)->as_string;
	debug("get next page_url: $page_url");
	push @{$self->urls}, $page_url;
    }

    $tree->delete;
    
    foreach my $url ( @urls ) {
	my $sku;
	if ( $url =~ m{product_id=(\d+)} ) {
	    $sku = $1;	
	} else {
	    next;
        }
	my $resp = $self->ua->get($url);

	my $content = $resp->decoded_content;
	my $sku_tree = HTML::TreeBuilder->new_from_content($content);

	my $item = Asthma::Item->new();

	$item->sku($sku);
	$item->url($url);

	if ( $sku_tree->look_down(_tag => 'h1') ) {
	    $item->title($sku_tree->look_down(_tag => 'h1')->as_trimmed_text);
	}

	if ( $sku_tree->look_down('id', 'd_price') ) {
	    $item->price($sku_tree->look_down('id', 'd_price')->as_trimmed_text);
	}

        #id="largePic"
	if ( $sku_tree->look_down('id', 'largePic') ) {
	    if ( $sku_tree->look_down('id', 'largePic')->attr('wsrc') ) {
		$item->image_url($sku_tree->look_down('id', 'largePic')->attr('wsrc'));
	    }
	}

	$sku_tree->delete;

	if ( $content =~ m{I S B N：</i>(\d+)} ) {
	    my $ean = $1;
	    $item->ean($ean);
	}

	debug_item($item);
	
        $self->add_item($item);
    }
}


__PACKAGE__->meta->make_immutable;

1;


