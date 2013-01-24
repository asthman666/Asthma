package Asthma::Spider::JingDongMobile;
use Moose;
extends 'Asthma::Spider';

use utf8;
use Asthma::Item;
use Asthma::Debug;
use HTML::TreeBuilder;
use URI;
#use Data::Dumper;

sub BUILD {
    my $self = shift;
    $self->site_id(102);
    $self->start_url('http://www.360buy.com/products/652-653-655.html');
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

    if ( my $content = $resp->decoded_content )  {
        my $tree = HTML::TreeBuilder->new_from_content($content);
        
        # find next page
        if ( $tree->look_down('class', 'pagin pagin-m') ) {
            if ( $tree->look_down('class', 'pagin pagin-m')->look_down("class", "next") ) {
                if ( my $page_url = $tree->look_down('class', 'pagin pagin-m')->look_down("class", "next")->attr("href") ) {
                    $page_url = URI->new_abs($page_url, $resp->base)->as_string;
                    debug("get next page_url: $page_url");
                    push @{$self->urls}, $page_url;
                }
            }
        }

        # parse list page
        my @chunks;
        if ( my $plist = $tree->look_down('id', 'plist') ) {
            @chunks = $plist->look_down(_tag => 'li', sku => qr/\d+/)
        }

        foreach my $c ( @chunks ) {
            my $item = Asthma::Item->new();
            if ( my $p = $c->look_down(class => "p-name") ) {
                if ( my $title = $p->as_trimmed_text ) {
                    $item->title($title);
                }
            }

            if ( my $sku = $c->attr("sku") ) {
                $item->sku($sku);
                $item->url("http://www.360buy.com/product/" . $sku . ".html");
                if ( my $price = $self->fprice($sku) ) {
                    $item->price($price);
                }
            }

            if ( my $p = $c->look_down(class => "p-img") ) {
                if ( my $img = $p->look_down(_tag => "img") ) {
                    if ( my $image_url = $img->attr("src") || $img->attr("src2") ) {
                        $item->image_url($image_url);
                    }
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

sub parse {
    
}

sub fprice {
    my $self = shift;
    my $sku  = shift;
    return unless $sku;
    my $price_url = "http://jprice.360buy.com/price/np" . $sku . "-TRANSACTION-J.html";

    my $pres = $self->ua->get($price_url);
    my $pcon = $pres->decoded_content;
    
    if ( $pcon =~ m/"jdPrice":\{.*?"amount"\s*:(.*?),/is ) {
        return $1;
    }

    return;
}

__PACKAGE__->meta->make_immutable;

1;


