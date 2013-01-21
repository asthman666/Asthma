package Asthma::Spider::SuningMobile;
use Moose;
extends 'Asthma::Spider';

use utf8;
use Asthma::Item;
use Asthma::Debug;
use HTML::TreeBuilder;
use AnyEvent;
use AnyEvent::HTTP;
use HTTP::Headers;
use HTTP::Message;
use Data::Dumper;

has 'start_url' => (is => 'rw', isa => 'Str');

sub BUILD {
    my $self = shift;
    $self->site_id(103);
    $self->start_url('http://search.suning.com/emall/strd.do?ci=20006');
}

sub run {
    my $self = shift;

    my $start_url = $self->start_url;

    foreach ( 0..20 ) {
        my $url = $start_url;
        $url .= "&cp=$_";
        my $resp = $self->ua->get($url);        
        $self->find($resp);
    }
}

sub find {
    my $self = shift;
    my $resp = shift;
    return unless $resp;
    
    debug("process: " . $resp->request->uri->as_string);

    my @plinks;

    if ( my $content = $resp->decoded_content ) {
        my $tree = HTML::TreeBuilder->new_from_content($content);
        
        foreach my $plist ( $tree->look_down("id", "proShow") ) {
            foreach my $item ( $plist->look_down(_tag => "li", id => qr/\d+/) ) {
                if ( my @item_links = $item->look_down(_tag => 'a') ) {
                    my $link = $item_links[0]->attr("href");
                    push @plinks, $link;
                }
            }
        }
        
        $tree->delete;
    }

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
	if ( $sku_tree->look_down(_tag => 'h1') ) {
            if ( my $title_span = $sku_tree->look_down(_tag => 'h1')->look_down(_tag => 'span') ) {
                if ( my @cons = $title_span->content_list ) {
                    if ( my $title = $cons[0] ) {
                        $item->title($title);
                    }
                }
            }
	}

	if ( $content =~ m{currPrice\s*=\s*(.*?)&} ) {
            my $price = $1;
            $item->price($price);
        } else {
	    $item->available('out of stock');
	}

        if ( $sku_tree->look_down('id', 'preView_box') ) {
            if ( my $li = $sku_tree->look_down('id', 'preView_box')->look_down(_tag => 'li', class => 'cur') ) {
                if ( $li->look_down(_tag => 'img') ) {
                    if ( my $image_url = $li->look_down(_tag => 'img')->attr("src") ) {
                        $item->image_url($image_url);
                    }
                }
            }
        }

	$sku_tree->delete;
    }

    return $item;
}

__PACKAGE__->meta->make_immutable;

1;


