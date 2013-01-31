package Asthma::Spider::LuSenMobile;
use Moose;
extends 'Asthma::Spider';

use utf8;
use Asthma::Item;
use Asthma::Debug;
use HTML::TreeBuilder;
use Data::Dumper;
use URI;

sub BUILD {
    my $self = shift;
    $self->site_id(113);
    $self->start_url('http://www.lusen.com/Product/ProductList.aspx?cid=10&pcl=3');
}

sub run {
    my $self = shift;

    my $start_url = $self->start_url;
    my $resp = $self->ua->get($start_url);
    my $render = $self->start_find($resp);
    return unless $render;

    foreach my $page ( 2..4 ) {
        debug("process page: $page");
        my $url = $start_url;
        my $post_json = "{action:'pageEvent',pageIndex:$page,pageSize:20,sortDirect:'',sortField:'',render:'$render',pb:'',pe:''}";
        my $resp = $self->ua->post( $url, 'Content' => $post_json, 'Content-Type' => 'application/json' );
        $self->find($resp);
    }
}

sub start_find {
    my $self = shift;
    my $resp = shift;
    return unless $resp;

    debug("process: " . $resp->request->uri->as_string);

    if ( my $content = $resp->decoded_content ) {
        my $tree = HTML::TreeBuilder->new_from_content($content);
        
        my @chunks;
        if ( my $list = $tree->look_down(id => 'listProduct') ) {
            @chunks = $list->look_down(_tag => "div", class => "shows");
        }

        $self->parse_chunks($resp, @chunks);

        if ( my $id = $tree->look_down("id", "listProduct_hide") ) {
            if ( my $v = $id->attr("value") ) {
                return $v;
            }
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
        my @chunks = $tree->look_down(_tag => "div", class => "shows");   
        $self->parse_chunks($resp, @chunks);
    }
}

sub parse_chunks {
    my $self = shift;
    my $resp = shift;
    return unless $resp;

    my @chunks = @_;
    foreach my $c ( @chunks ) {
        my $item = Asthma::Item->new();

        if ( my $p = $c->look_down("class", "imgtit") ) {
            if ( my $title = $p->as_trimmed_text ) {
                $item->title($title);
            }
            if ( my $a = $p->look_down(_tag => 'a') ) {
                if ( my $url = $a->attr("href") ) {
                    $url = URI->new_abs($url, $resp->base)->as_string;
                    if ( $url =~ m{ProductInfo\.aspx\?Id=(\d+)} ) {
                        my $sku = $1;
                        $item->sku($sku);
                        $item->url($url);
                    }
                }
            }
        }

        if ( my $p = $c->look_down("class", "imgpri") ) {
            if ( my $pp = $p->look_down("class", "new") ) {
                if ( my $price = $pp->as_trimmed_text ) {
                    $item->price($price);
                }
            }
        }

        debug_item($item);
        $self->add_item($item);
    }}

__PACKAGE__->meta->make_immutable;

1;



