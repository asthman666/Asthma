package Asthma::Spider::FeihuMobile;

use Moose;
extends 'Asthma::Spider';

use utf8;
use Asthma::Item;
use HTML::TreeBuilder;
use URI;
use Asthma::Debug;

sub BUILD {
    my $self = shift;
    $self->site_id(111);
    $self->start_url('http://www.efeihu.com/Products/89-0-0-0-0-0-40--1.html');
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

    if ( my $content = $resp->decoded_content ) {
        my $tree = HTML::TreeBuilder->new_from_content($content);

        if ( my @nexts = $tree->look_down(_tag => 'a', class => 'btn_next') ) {
	    foreach my $next ( @nexts ) {
		if ( $next->as_trimmed_text eq '下一页' ) {
		    if ( my $page_url = $next->attr("href") ) {
			$page_url = URI->new_abs($page_url, $resp->base)->as_string;
			debug("get next page_url: $page_url");
			push @{$self->urls}, $page_url;
			last;
		    }
		}
	    }
        }
        
        my @chunks;
        if ( my $plist = $tree->look_down('id', 'prolist') ) {
            @chunks = $plist->look_down(_tag => 'li', class => 'm_pro');
        }

        foreach my $c ( @chunks ) {
            my $item = Asthma::Item->new();
            if ( my $a = $c->look_down(_tag => 'a', class => "name") ) {
                if ( my $title = $a->as_trimmed_text ) {
                    $item->title($title);
                }
            }

            if ( my $p = $c->look_down(class => "priceNum") ) {
		if ( my $price = $p->as_trimmed_text ) {
		    $item->price($price);
		}
            }

            if ( my $a = $c->look_down(_tag => 'a', class => "img") ) {
		my $url = $a->attr("href");
		$url = URI->new_abs($url, $resp->base)->as_string;
		if ( $url =~ m{/Product/(\d+)\.html} ) {
		    my $sku = $1;
		    $item->sku($sku);
		    $item->url($url);
		}
            }

            my $con = $c->as_trimmed_text;
	    if ( $con =~ m{到货通知} ) {
                $item->available('out of stock');
	    }
	    
            debug_item($item);
            $self->add_item($item);
        }

        $tree->delete;
    }
}


__PACKAGE__->meta->make_immutable;

1;



