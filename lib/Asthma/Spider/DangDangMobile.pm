package Asthma::Spider::DangDangMobile;

use Moose;
extends 'Asthma::Spider';

use utf8;
use Asthma::Item;
use HTML::TreeBuilder;
use URI;
use Asthma::Debug;

sub BUILD {
    my $self = shift;
    $self->site_id(101);
    $self->start_url('http://category.dangdang.com/all/?att=22277%3A1&category_id=4004279');
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

        if ( my $next = $tree->look_down(class => 'next') ) {
            if ( my $a = $next->look_down(_tag => 'a') ) {
                if ( my $page_url = $a->attr("href") ) {
                    $page_url = URI->new_abs($page_url, $resp->base)->as_string;
                    debug("get next page_url: $page_url");
                    push @{$self->urls}, $page_url;
                }
            }
        }
        
        my @chunks;
        if ( my $plist = $tree->look_down('class', 'shoplist') ) {
            @chunks = $plist->look_down(_tag => 'li', name => 'lb');
        }

        foreach my $c ( @chunks ) {
            my $item = Asthma::Item->new();
            if ( my $p = $c->look_down(_tag => 'p', class => "name") ) {
                if ( my $title = $p->as_trimmed_text ) {
                    $item->title($title);
                }
            }

            if ( my $p = $c->look_down(class => "price") ) {
                if ( my $pr = $p->look_down(class => "price_n") ) {
                    if ( my $price = $pr->as_trimmed_text ) {
			if ( $price =~ m{\-} ) {
			    $item->price((split(/\-/, $price))[0]);
			} else {
			    $item->price($price);
			}
                    }
                }
            }

            if ( my $p = $c->look_down(class => "inner") ) {
                if ( my $a = $p->look_down(_tag => "a") ) {
                    if ( my $url = $a->attr("href") ) {
                        if ( $url =~ m{product_id=(\d+)} ) {
                            my $sku = $1;
                            $item->sku($sku);
                            $item->url($url);
                            if ( my $ava = $self->get_stock($sku) ) {
                                $item->available($ava);
                            }
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

sub get_stock {
    my $self = shift;
    my $sku  = shift;
    return unless $sku;
    my $url = "http://product.dangdang.com/callback.php?product_id=$sku&type=stock";
    my $resp = $self->ua->get($url);
    my $content = $resp->decoded_content;
    use JSON;
    my $ref = decode_json($content);

    #use Data::Dumper;debug Dumper $ref;

    if ( $ref->{havestock} && $ref->{havestock} eq 'presale' ) {
        return 'pre order';
    }
    return;
}

__PACKAGE__->meta->make_immutable;

1;




