package Asthma::Spider::JingDong;
use Moose;
extends 'Asthma::Spider';

use utf8;
use Asthma::LinkExtractor;
use Asthma::Item;
use HTML::TreeBuilder;
use URI;
use Asthma::Debug;
use AnyEvent;
use AnyEvent::HTTP;
use HTTP::Headers;
use HTTP::Message;
use Data::Dumper;

has 'start_url' => (is => 'rw', isa => 'Str');
has 'link_extractor' => (is => 'rw', lazy_build => 1);

sub _build_link_extractor {
    my $self = shift;
    return Asthma::LinkExtractor->new();
}

sub BUILD {
    my $self = shift;
    $self->site_id(102);
    $self->start_url('http://www.360buy.com/book/booksort.aspx');
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

    my $content = $resp->decoded_content;
    
    my $tree = HTML::TreeBuilder->new_from_content($content);
    # class="w main"
    if ( my $main = $tree->look_down("class", "w main") ) {
	if ( my @dts = $main->look_down(_tag => 'dt') ) {
	    foreach my $dt ( @dts ) {
		if ( $dt->look_down(_tag => 'a') ) {
		    my $link = $dt->look_down(_tag => 'a')->attr("href");
		    # NOTE: only want to get browse link
		    if ( $link =~ s{(\d+)-\d+\.html}{$1-$1\.html} ) {
			push @{$self->urls}, $link;
		    }
		}
	    }
	}
    }
    
    if ( $tree->look_down('class', 'pagin pagin-m') ) {
	if ( $tree->look_down('class', 'pagin pagin-m')->look_down("class", "next") ) {
	    my $page_url = $tree->look_down('class', 'pagin pagin-m')->look_down("class", "next")->attr("href");
	    debug("get next page_url: $page_url");
	    push @{$self->urls}, $page_url;
	}
    }
    
    # id="plist">
    # <a target='_blank' href="http://book.360buy.com/10658646.html">

    my @plinks;
    foreach my $plist ( $tree->look_down("id", "plist") ) {
	foreach my $item ( $plist->look_down('class', 'item') ) {
	    if ( my @item_links = $item->look_down(_tag => 'a') ) {
		my $link = $item_links[0]->attr("href");
		push @plinks, $link;
	    }
	}
    }
    
    $tree->delete;

    #debug("product links: " . Dumper \@plinks);

    if ( @plinks ) {
	my $cv = AnyEvent->condvar;

	foreach my $url ( @plinks ) {
	    my $sku;
	    if ( $url =~ m{(\d+)\.html} ) {
		$sku = $1;
	    }

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


        #<li ><span>ＩＳＢＮ：</span>9787544253994</li>
	if ( $content =~ m{ＩＳＢＮ：(.*?)</li>} ) {
	    my $ean = $1;
	    $item->ean($ean);
	}
	
	# 京东价：￥29.60
	if ( $content =~ m{京东价：￥([\d.]+)} ) {
	    my $price = $1;
	    $item->price($price);
	}
	
	# var img = "http://img10.360buyimg.com/n1/19902/8e48330f-24c6-4991-a0aa-2a40fb100e3e.jpg";
	if ( $content =~ m{var\s+img\s+=\s+"(.*?)"} ) {
	    my $image_url = $1;
	    $item->image_url($image_url);
	}

	$sku_tree->delete;
    }

    return $item;
}

__PACKAGE__->meta->make_immutable;

1;
