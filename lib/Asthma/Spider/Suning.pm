package Asthma::Spider::Suning;
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
use Data::Dumper;

has 'start_url' => (is => 'rw', isa => 'Str');

sub BUILD {
    my $self = shift;
    $self->site_id(103);
    $self->start_url('http://search.suning.com/emall/trd.do?ci=226503');
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

    my $content = $resp->decoded_content;

    my $tree = HTML::TreeBuilder->new_from_content($content);
    
    if ( $tree->look_down('class', 'next') ) {
        my $page_url = $tree->look_down('class', 'next')->attr("href");
        $page_url = URI->new_abs($page_url, $resp->base)->as_string;
        debug("get next page_url: $page_url");
        push @{$self->urls}, $page_url;
    }
    
    my @plinks;
    foreach my $plist ( $tree->look_down("id", "proList") ) {
	foreach my $item ( $plist->look_down(_tag => "li") ) {
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
	    if ( $url =~ m{([^/]+)\.html} ) {
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
		my $content = $mess->decoded_content(charset => 'utf-8');
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
	if ( $sku_tree->look_down(_tag => 'h3', class => 'title') ) {
            if ( $sku_tree->look_down(_tag => 'h3', class => 'title')->look_down(_tag => 'span') ) {
                $item->title($sku_tree->look_down(_tag => 'h3', class => 'title')->look_down(_tag => 'span')->as_trimmed_text);
            } else {
                $item->title($sku_tree->look_down(_tag => 'h3', class => 'title')->as_trimmed_text);
            }
	}

	if ( $content =~ m{<th>&nbsp;I&nbsp;S&nbsp;B&nbsp;N&nbsp;：</th><td>(\d+)} ) {
	    my $ean = $1;
	    $item->ean($ean);
	}
	
	if ( $content =~ m{currPrice\s*:\s*"(.*?)"} ) {
            my $price = $1;
            $item->price($price);
        }
	
        if ( $sku_tree->look_down(class => "bookFourthThum") ) {
            if ( my $img = $sku_tree->look_down(class => "bookFourthThum")->look_down(_tag => 'img') ) {
                my $image_url = $img->attr("src");
                $item->image_url($image_url);
            }
        }

	$sku_tree->delete;
    }

    return $item;
}

__PACKAGE__->meta->make_immutable;

1;

