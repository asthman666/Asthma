package Asthma::Spider::FeihuMobile;

use Moose;
extends 'Asthma::Spider';

use utf8;
use Asthma::Item;
use HTML::TreeBuilder;
use URI;
use Asthma::Debug;
use Coro;
use AnyEvent::HTTP;

sub BUILD {
    my $self = shift;
    $self->site_id(111);
    $self->start_url('http://www.efeihu.com/Pages/all.aspx');
}

sub run {
    my $self = shift;

    $self->find_start_urls;

    my $i;
    while ( 1 ) {
	$i++;
	my $time = time;
	$self->ifind;
	debug("loop $i done, cost " . (time - $time));
	last unless @{$self->urls};
        last if $self->depth && $i >= $self->depth;
    }
}

sub find_start_urls {
    my $self = shift;
    my $resp = $self->ua->get($self->start_url);
    if ( my $content = $resp->decoded_content ) {
        my $tree = HTML::TreeBuilder->new_from_content($content);
        # <div class="brand_item_childs">
        foreach my $div ( $tree->look_down(_tag => 'div', class => 'brand_item_childs') ) {
            foreach my $dd ( $div->look_down(_tag => 'dd') ) {
                if ( my $link = $dd->look_down(_tag => 'a') ) {
                    if ( my $url = $link->attr("href") ) {
                        $url = URI->new_abs($url, $resp->base)->as_string;
                        push @{$self->urls}, $url;
                        #return;
                    }
                }
            }
        }
    }
}

sub ifind {
    my $self = shift;

    my $sem = Coro::Semaphore->new(5);
    
    my @coros;
    my $run = 1;
    while ( $run ) {
	if ( my $url = pop(@{$self->urls}) ) {
	    push @coros,
	    async {
		my $guard = $sem->guard;

		http_get $url, 
		headers => $self->headers,
		Coro::rouse_cb;

		my ($body, $hdr) = Coro::rouse_wait;

		my $url = $hdr->{URL};
		
		debug("process $url");

		my $header = HTTP::Headers->new('content-type' => 'text/html');
		my $mess = HTTP::Message->new( $header, $body );
		if ( my $content = $mess->decoded_content(charset => 'gbk') ) {
                    my $tree = HTML::TreeBuilder->new_from_content($content);

                    if ( my @nexts = $tree->look_down(_tag => 'a', class => 'btn_next') ) {
                        foreach my $next ( @nexts ) {
                            if ( $next->as_trimmed_text eq '下一页' ) {
                                if ( my $page_url = $next->attr("href") ) {
                                    $page_url = URI->new_abs($page_url, $url)->as_string;
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
                            my $item_url = $a->attr("href");
                            $item_url = URI->new_abs($item_url, $url)->as_string;
                            if ( $item_url =~ m{/Product/(\d+)\.html} ) {
                                my $sku = $1;
                                $item->sku($sku);
                                $item->url($item_url);
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
	} else {
	    $run = 0;
	}
    }

    $_->join foreach ( @coros );        


}

__PACKAGE__->meta->make_immutable;

1;

