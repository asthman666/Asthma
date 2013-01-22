package Asthma::Spider::YiXunMobile;

use Moose;
extends 'Asthma::Spider';

use utf8;
use Asthma::Item;
use Asthma::Debug;
use HTML::TreeBuilder;

has 'start_url' => (is => 'rw', isa => 'Str');

sub BUILD {
    my $self = shift;
    $self->site_id(105);
    $self->start_url('http://list.51buy.com/311--------.html');
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
        # <ul class="list_goods">
        my @chunks;
        if ( my $list = $tree->look_down(_tag => "ul", class => "list_goods") ) {
            @chunks = $list->look_down(_tag => "li", class => "item_list");
        }

        foreach my $c ( @chunks ) {
            my $item = Asthma::Item->new();
            
            # class="link_name">
            if ( $c->look_down('class', 'link_name') ) {
                my $title = $c->look_down('class', 'link_name')->as_trimmed_text;
                $item->title($title);
            }

            # class="price_icson"
            if ( my $p = $c->look_down('class', 'price_icson') ) {
                if ( $p->look_down('class', 'hot') ) {
                    if ( my $price = $p->look_down('class', 'hot')->as_trimmed_text ) {
                        $item->price($price);
                    }
                }
            }

            if ( my $pic = $c->look_down("class", "link_pic") ) {
                if ( my $url = $pic->attr("href") ) {
                    if ( $url =~ m{item-(\d+)\.html} ) {
                        $item->url($url);
                        my $sku = $1;
                        $item->sku($sku);
                    }
                }
            }

            if ( $content =~ m{<img _src="(.+?)"} ) {
                my $image_url = $1;
                $item->image_url($image_url);
            }

            if ( $content =~ m{到货通知} ) {
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

