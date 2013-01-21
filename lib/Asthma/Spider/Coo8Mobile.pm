package Asthma::Spider::Coo8Mobile;

use Moose;
extends 'Asthma::Spider';
with 'Asthma::Tool';

use utf8;
use Asthma::Item;
use Asthma::Debug;
use HTML::TreeBuilder;

has 'start_url' => (is => 'rw', isa => 'Str');

sub BUILD {
    my $self = shift;
    $self->site_id(104);
    $self->start_url('http://www.coo8.com/products/290-0-0-0-0.html');
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

    debug("process: " . $resp->request->uri->as_string);

    if ( my $tree = HTML::TreeBuilder->new_from_content($content) ) {
        if ( $tree->look_down('class', 'page-next') ) {
            if ( my $page_url = $tree->look_down('class', 'page-next')->attr('href') ) {
		debug("get next page_url: $page_url");
		push @{$self->urls}, $page_url;
	    }
        }

        # parse list page
        my @chunks;
        if ( my @lists = $tree->look_down(_tag => "ul", class => "product-items clearfix") ) {
            if ( my $list = $lists[1] ) {
                @chunks = $list->look_down(_tag => "li");
            }
        }

        foreach my $c ( @chunks ) {
            my $item = Asthma::Item->new();
            if ( my $p = $c->look_down(_tag => "p", class => "name") ) {
                if ( my $a = $p->look_down(_tag => "a") ) {
                    if ( my $em = $a->look_down(_tag => "em") ) {
                        $em->delete;
                    }
                    if ( my $title = $a->as_trimmed_text ) {
                        $item->title($title);
                    }
                }
            }

            if ( my $p = $c->look_down(_tag => "p", class => "name") ) {
                if ( my $a = $p->look_down(_tag => "a") ) {
                    if ( my $url = $a->attr("href") ) {
                        $item->url($url);
                        if ( $url =~ m{(\d+)\.html} ) {
                            my $sku = $1;
                            $item->sku($sku);
                        }
                    }
                }
            }

            if ( my $p = $c->look_down(_tag => "p", class => "pic") ) {
                if ( my $img = $p->look_down(_tag => "img") ) {
                    if ( my $image_url = $img->attr("src") ) {
                        $item->image_url($image_url);
                    }
                }
            }

            if ( my $p = $c->look_down(_tag => "p", class => "price") ) {
                if ( my $img = $p->look_down(_tag => "img") ) {
                    if ( my $price_url = $img->attr("src") ) {
                        if ( my $price = $self->get_price($price_url) ) {
                            $item->price($price);
                        }
                    }
                }
            }
            debug_item($item);
            $self->add_item($item);
        }
        
        $tree->delete;
    }
}

__PACKAGE__->meta->make_immutable;

1;



