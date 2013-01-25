package Asthma::Spider::New7Mobile;

use Moose;
extends 'Asthma::Spider';

use utf8;
use Asthma::Item;
use Asthma::Debug;
use HTML::TreeBuilder;
use URI;
use AnyEvent;
use AnyEvent::HTTP;
use HTTP::Headers;
use HTTP::Message;

sub BUILD {
    my $self = shift;
    $self->site_id(110);
    $self->start_urls(['http://www.new7.com/products/102.html', 
                       'http://www.new7.com/products/146.html',
                       'http://www.new7.com/products/147.html',
                       'http://www.new7.com/products/148.html',
                       'http://www.new7.com/products/150.html',
                       'http://www.new7.com/products/151.html',
                      ]);
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


    debug("process: " . $resp->request->uri->as_string);

    if ( my $content = $resp->decoded_content ) {
        my $tree = HTML::TreeBuilder->new_from_content($content);
        # class="newSearchPaging"
        if ( my $page = $tree->look_down('class', 'newSearchPaging') ) {
            if ( my $npage = $page->look_down('class', 'bottom') ) {
                if ( my $page_url = $npage->attr("href") ) {
                    $page_url = URI->new_abs($page_url, $resp->base)->as_string;
                    debug("get next page_url: $page_url");
                    push @{$self->urls}, $page_url;
                }
            }
        }

        my @plinks;

        # class="likeProduct">
        if ( my $plist = $tree->look_down("class", "likeProduct") ) {
            if ( my @lis = $plist->look_down(_tag => 'li') ) {
                foreach my $li ( @lis ) {
                    if ( my $name = $li->look_down("class", "productName") ) {
                        if ( my $a = $name->look_down(_tag => 'a') ) {
                            if ( my $plink = $a->attr("href") ) {
                                $plink = URI->new_abs($plink, $resp->base)->as_string;
                                push @plinks, $plink;
                            }
                        }
                    }
                }
            }
        }

        #use Data::Dumper;debug Dumper \@plinks;
        
        $tree->delete;

        my $cv = AnyEvent->condvar;

        foreach my $url ( @plinks ) {
	    my $sku;
	    if ( $url =~ m{product/(\d+)\.html} ) {
		$sku = $1;
	    }

            $cv->begin;

            http_get $url, 
            headers => {
                "user-agent" => "Mozilla/5.0 (Windows NT 6.1; rv:17.0) Gecko/20100101 Firefox/17.0",
                'Accept-Language' => "zh-cn,zh;q=0.8,en-us;q=0.5,en;q=0.3",
                'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            },

            sub {
                my ( $body, $hdr ) = @_;
                
                my $header = HTTP::Headers->new('content-type' => 'text/html');
                my $mess = HTTP::Message->new( $header, $body );
                my $content = $mess->decoded_content;
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
            if ( my $title = $sku_tree->look_down(_tag => 'h1')->as_trimmed_text ) {
                $item->title($title);
            }
	}
        
        # <div class="mainR">
        if ( my $main = $sku_tree->look_down('class', 'mainR') ) {
            if ( my $p = $main->look_down('class', 'price') ) {
                if ( my $span = $p->look_down(_tag => 'span') ) {
                    if ( my $price = $span->as_trimmed_text ) {
                        $item->price($price);
                    }
                }
            }            
        }

        if ( $content =~ m{本款商品暂时无货} ) {
            $item->available("out of stock");
        }

	$sku_tree->delete;
    }

    return $item;
}

__PACKAGE__->meta->make_immutable;

1;


