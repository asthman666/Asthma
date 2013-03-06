package Asthma::Spider::NeweggMobile;

use Moose;
extends 'Asthma::Spider';

use utf8;
use Asthma::Item;
use Asthma::Debug;
use HTML::TreeBuilder;
use Coro;
use AnyEvent::HTTP;

sub BUILD {
    my $self = shift;
    $self->site_id(106);
    $self->start_url('http://www.newegg.com.cn/CategoryList.htm');
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
	# <div class="allCateList">
        foreach my $div ( $tree->look_down(_tag => 'div', class => 'allCateList') ) {
            foreach my $em ( $div->look_down(_tag => 'em') ) {
                if ( my $link = $em->look_down(_tag => 'a') ) {
                    if ( my $url = $link->attr("href") ) {
                        push @{$self->urls}, $url;
			#return if @{$self->urls} >= 5;
                        #return;
                    }
                }
            }
        }
    }
}

sub ifind {
    my $self = shift;

    my $sem = Coro::Semaphore->new(10);
    
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
		debug("process: $hdr->{Status} $hdr->{Reason} $hdr->{URL}");

		my $url = $hdr->{URL};

		my $header = HTTP::Headers->new('content-encoding' => "gzip, deflate", 'content-type' => 'text/html');
		my $mess = HTTP::Message->new( $header, $body );
		if ( my $content = $mess->decoded_content(charset => 'gbk') ) {
		    my $tree = HTML::TreeBuilder->new_from_content($content);
		    
		    if ( $tree->look_down('class', 'next') ) {
			if ( my $page_url = $tree->look_down('class', 'next')->attr('href') ) {
			    debug("get next page_url: $page_url");
			    push @{$self->urls}, $page_url;
			}
		    }

		    # parse list page
		    my @chunks;
		    if ( my $list = $tree->look_down(id => 'itemGrid1') ) {
			@chunks = $list->look_down(_tag => "div", sub {$_[0]->attr("class") eq  "itemCell noSeller" or $_[0]->attr("class") eq "itemCell " });
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
				if ( my $item_url = $a->attr("href") ) {
				    if ( $item_url =~ m{Product/([^<]+)\.htm} ) {
					my $sku = $1;
					$item->url($item_url);
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
	} else {
	    $run = 0;
	}
    }

    $_->join foreach ( @coros );        
}

__PACKAGE__->meta->make_immutable;

1;

