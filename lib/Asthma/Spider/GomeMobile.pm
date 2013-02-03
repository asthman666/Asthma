package Asthma::Spider::GomeMobile;
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

has 'json_ua' => (is => 'rw', isa => 'LWP::UserAgent', lazy_build => 1);

sub _build_json_ua {
    my $ua = LWP::UserAgent->new();
    $ua->agent('Mozilla/5.0 (Windows NT 5.1; rv:18.0) Gecko/20100101 Firefox/18.0');
    $ua->default_header('Accept' => 'application/json, text/javascript, */*');	
    $ua->default_header('Accept-Language' => 'zh-cn,zh;q=0.8,en-us;q=0.5,en;q=0.3');	
    $ua->default_header('Accept-Encoding' => 'gzip, deflate');
    $ua->default_header('X-Requested-With' => 'XMLHttpRequest');
    return $ua;
}

sub BUILD {
    my $self = shift;
    $self->site_id(103);
    $self->start_url('http://www.gome.com.cn/ec/homeus/jump/category/cat10000070-1-1-1-1-1-1.html');
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

    my @plinks;

    if ( my $content = $resp->decoded_content ) {
        my $tree = HTML::TreeBuilder->new_from_content($content);

	#debug $content;

	if ( my @ps = $tree->look_down(_tag => 'a', class => 'pr page-next') ) {
	    foreach my $p ( @ps ) {
		if ( $p->attr("href") && $p->attr("href") !~ m{javascript} ) {
		    my $page_url = $p->attr("href");
		    $page_url = URI->new_abs($page_url, $resp->base)->as_string;
		    debug("get next page_url: $page_url");
		    push @{$self->urls}, $page_url;
		    last;
		}
	    }
	}

	#debug $content;
        
        foreach my $plist ( $tree->look_down("class", "js-tabtit_data") ) {
            foreach my $item ( $plist->look_down(_tag => "li") ) {
                if ( my $item_link = $item->look_down(_tag => 'a') ) {
                    my $link = $item_link->attr("href");
		    $link = URI->new_abs($link, $resp->base)->as_string;
		    next if $link =~ m{javascript};
		    $link =~ s{;jsessionid=[^?]+}{};
                    push @plinks, $link;
                }
            }
        }
        
        $tree->delete;
    }

    debug("product links num: " . @plinks . ", " . Dumper \@plinks);

    if ( @plinks ) {
	my $cv = AnyEvent->condvar;

	foreach my $url ( @plinks ) {
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

		if ($hdr->{Status} ne '200') {
		    debug Dumper $hdr;
		}
		
		my $header = HTTP::Headers->new('content-encoding' => "gzip, deflate", 'content-type' => 'text/html');
		my $mess = HTTP::Message->new( $header, $body );
		my $content = $mess->decoded_content(charset => 'utf-8');
		my $item = $self->parse($content);

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
	if ( my $p = $sku_tree->look_down('id', 'prdtitle') ) {
	    if ( my $title = $p->as_trimmed_text ) {
		$item->title($title);
	    }
	}
	
	# <span id="sprodNum">1000281832</span>
	if ( my $p = $sku_tree->look_down('id', 'sprodNum') ) {
	    if ( my $sku = $p->as_trimmed_text ) {
		$item->sku($sku);
	    }
	}

	if ( $content =~ m{entity.value=([\d.]+)} ) {
	    my $price = $1;
	    $item->price($price);
	}

	my $site_id;
	if ( my $p = $sku_tree->look_down('id', 'siteId_p') ) {
	    $site_id = $p->attr("value");
	}
	
	my $sku_type;
	if ( my $p = $sku_tree->look_down('id', 'skuType_p') ) {
	    $sku_type = $p->attr("value");
	}
	
	my $she;
	if ( my $p = $sku_tree->look_down('id', 'shelfCtgy3') ) {
	    $she = $p->attr("value");
	}

	if ( my $ava = $self->get_stock($item->sku, $site_id, $sku_type, $she) ) {
	    $item->available($ava);
	}
	
	$sku_tree->delete;
    }

    return $item;
}

sub get_stock {
    my $self = shift;
    my $sku  = shift;
    my $site_id = shift;
    my $sku_type = shift;
    my $she = shift;
    return unless $sku && $site_id && $sku_type && $she;

    my $url =  "http://www.gome.com.cn/ec/homeus/browse/exactMethod.jsp?goodsNo=$sku&city=11010500&siteId_p=$site_id&skuType_p=$sku_type&shelfCtgy3=$she";
    my $resp = $self->ua->get($url);
    my $content = $resp->decoded_content;

    if ( $content =~ m{"result":"N"} ) {
	return 'out of stock';
    }

    return;
}

__PACKAGE__->meta->make_immutable;

1;



