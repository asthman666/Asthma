package Asthma::Spider::NeweggMobile;

use Moose;
extends 'Asthma::Spider';

use utf8;
use Asthma::Item;
use Asthma::Debug;
use HTML::TreeBuilder;

sub BUILD {
    my $self = shift;
    $self->site_id(106);
    $self->start_urls(['http://www.newegg.com.cn/SubCategory/1043.htm', 'http://www.newegg.com.cn/SubCategory/1046.htm', 'http://www.newegg.com.cn/SubCategory/2052.htm']);
}

sub run {
    my $self = shift;

    foreach my $start_url ( @{$self->start_urls} ) {
	my $resp = $self->ua->get($start_url);
	$self->find($resp);
    }

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
	# class='selected noBdrBot'
        if ( $tree->look_down('class', 'next') ) {
            if ( my $page_url = $tree->look_down('class', 'next')->attr('href') ) {
                debug("get next page_url: $page_url");
                push @{$self->urls}, $page_url;
            }
        }

        # parse list page
        my @chunks;
        if ( my $list = $tree->look_down(id => 'itemGrid1') ) {
            @chunks = $list->look_down(_tag => "div", class => "itemCell noSeller");
        }

        foreach my $c ( @chunks ) {
            my $item = Asthma::Item->new();
            
	    if ( my $i = $c->look_down(_tag => 'img', sub {defined $_[0]->attr("title")} ) ) {
		if ( my $image_url = $i->attr("src") ) {
		    $item->image_url($image_url);
		}
	    }

	    # class="info"
            if ( my $in = $c->look_down('class', 'info') ) {
		if ( my $a = $in->look_down(_tag => 'a') ) {
		    if ( my $url = $a->attr("href") ) {
			if ( $url =~ m{Product/([^<]+)\.htm} ) {
			    my $sku = $1;
			    $item->url($url);
			    $item->sku($sku);
			}
		    }
		}

                if ( my $title = $in->as_trimmed_text ) {
		    $item->title($title);
		}
            }

            if ( my $p = $c->look_down(_tag => 'strong', class => 'price') ) {
		if ( my $price = $p->as_trimmed_text ) {
		    $item->price($price);
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

