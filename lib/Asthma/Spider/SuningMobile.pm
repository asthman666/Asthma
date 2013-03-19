package Asthma::Spider::SuningMobile;
use Moose;
extends 'Asthma::Spider';

use utf8;
use Asthma::Item;
use Asthma::Debug;
use HTML::TreeBuilder;
use Coro;
use AnyEvent::HTTP;
use HTTP::Headers;
use HTTP::Message;
use Data::Dumper;

has 'json_headers' => (is => 'rw', isa => 'HashRef', 
                       default => sub {
                           {
                               'user-agent' => 'Mozilla/5.0 (Windows NT 6.1; rv:17.0) Gecko/20100101 Firefox/17.0',
                               'Accept' => 'application/json, text/javascript, */*',
                               "Accept-Encoding" => "gzip, deflate",
                               'Accept-Language' => "zh-cn,zh;q=0.8,en-us;q=0.5,en;q=0.3",
                               'X-Requested-With' => 'XMLHttpRequest',
                           }
                       });

sub BUILD {
    my $self = shift;
    $self->site_id(103);
    $self->start_url('http://www.suning.com/emall/pgv_10052_10051_1_.html');
}

sub run {
    my $self = shift;

    $self->storage->redis->del($self->site_id);

    $self->find_start_urls;

    my $i;
    while ( 1 ) {
	$i++;
	my $time = time;
	$self->ifind;
	$self->ido;
        my $length = $self->storage->redis->llen($self->site_id);
        debug("$length items url in redis");
	debug("loop $i done, cost " . (time - $time));
	last unless @{$self->urls} || $length;
        last if $self->depth && $i >= $self->depth;
    }
}

sub find_start_urls {
    my $self = shift;
    my $resp = $self->ua->get($self->start_url);

    my %ca = map {$_ => 1} (2..13);
    
    if ( my $content = $resp->decoded_content ) {
        my $tree = HTML::TreeBuilder->new_from_content($content);
        my $i;
        foreach my $div ( $tree->look_down(_tag => 'div', class => 'listLeft') ) {
            $i++;
            if ( $ca{$i} ) {
                foreach my $dd ( $div->look_down(_tag => 'dd') ) {
                    foreach my $link ( $dd->look_down(_tag => 'a') ) {
                        if ( my $url = $link->attr("href") ) {
                            $url =~ s{&cityId=\{cityId\}}{}ig;
                            if ( $url =~ m{^http://search\.suning\.com/emall/strd\.do\?ci=(\d+)$} ) {
                                push @{$self->urls}, $url;
                            } else {
                                debug("$url can't match category url regex");
                            }
                            #return;
                        }
                    }
                }
            }
        }
    }
}

sub ifind {
    my $self = shift;

    my $sem = Coro::Semaphore->new(30);
    
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

		my $header = HTTP::Headers->new('content-encoding' => "gzip, deflate", 'content-type' => 'text/html');
		my $mess = HTTP::Message->new( $header, $body );

                my @plinks;
		if ( my $content = $mess->decoded_content ) {
                    my $tree = HTML::TreeBuilder->new_from_content($content);

                    # NOTE: find next page
                    # <span><i id="pageThis">1</i>/<i id="pageTotal">15</i></span>
		    if ( $tree->look_down('id', 'pageThis') ) {
                        my $page_cur = $tree->look_down('id', 'pageThis')->as_trimmed_text;
                        my $page_total = $tree->look_down('id', 'pageTotal')->as_trimmed_text;

                        if ( $page_cur < $page_total ) {
                            my $next_page_no = $page_cur;
                            $url =~ s{&?cp=\d+}{}g;
                            my $page_url = $url . "&cp=$next_page_no";
                            debug("get next page_url: $page_url");
                            push @{$self->urls}, $page_url;
                        }
		    }

                    # NOTE: find item page
                    foreach my $plist ( $tree->look_down("id", "proShow") ) {
                        foreach my $item ( $plist->look_down(_tag => "li", id => qr/\d+/) ) {
                            if ( my @item_links = $item->look_down(_tag => 'a') ) {
                                my $link = $item_links[0]->attr("href");
                                push @plinks, $link;
                            }
                        }
                    }
                    $tree->delete;
                }

                #debug("product links: " . Dumper \@plinks);

                foreach my $url ( @plinks ) {
                    $self->storage->redis->rpush($self->site_id, $url);
                }
	    }
	} else {
	    $run = 0;
	}
    }

    $_->join foreach ( @coros );        
}

sub ido {
    my $self = shift;
    
    my $sem = Coro::Semaphore->new(30);

    my $i;

    my @coros;
    my $run = 1;
    while ( $run ) {
	if ( my $url = $self->storage->redis->lpop($self->site_id) ) {
            $i++;
	    next if $url !~ m{([^/]+)\.html};
	    my $sku = $1;
	    
	    push @coros,
	    async {
		my $guard = $sem->guard;
                
		http_get $url, 
		headers => $self->headers,
		Coro::rouse_cb;

		my ($body, $hdr) = Coro::rouse_wait;
		debug("$hdr->{Status} $hdr->{Reason} $hdr->{URL}");
		
		my $header = HTTP::Headers->new('content-encoding' => "gzip, deflate", 'content-type' => 'text/html');
		my $mess = HTTP::Message->new( $header, $body );
		my $content = $mess->decoded_content(charset => 'utf-8');

		my $item = $self->parse($content);
		
		$item->sku($sku);
		$item->url($url);
                return $item;
	    }
	} else {
	    $run = 0;
	}

        $run = 0 if $i >= 100;
    }

    my @items;
    
    foreach ( @coros ) {
        my $item = $_->join;
        push @items, $item;
    }

    # get price
    $self->fprice(@items);
    
    # get stock
    $self->get_stock(@items);
}

sub parse {
    my $self    = shift;
    my $content = shift;

    my $item = Asthma::Item->new();

    if ( $content ) {
	my $sku_tree = HTML::TreeBuilder->new_from_content($content);
	if ( $sku_tree->look_down(_tag => 'h1') ) {
            if ( my $title_span = $sku_tree->look_down(_tag => 'h1')->look_down(_tag => 'span') ) {
                if ( my @cons = $title_span->content_list ) {
                    if ( my $title = $cons[0] ) {
                        $item->title($title);
                    }
                }
            }
	}

        if ( $content =~ m{"partNumber":"(\d+)"}) {
	    $item->extra->{part_num} = $1;
        }

        if ( $sku_tree->look_down('id', 'preView_box') ) {
            if ( my $li = $sku_tree->look_down('id', 'preView_box')->look_down(_tag => 'li', class => 'cur') ) {
                if ( $li->look_down(_tag => 'img') ) {
                    if ( my $image_url = $li->look_down(_tag => 'img')->attr("src") ) {
                        $item->image_url($image_url);
                    }
                }
            }
        }

	$sku_tree->delete;
    }

    return $item;
}

sub fprice {
    my $self  = shift;
    my @items = @_;
    
    my $sem = Coro::Semaphore->new(30);

    my @coros;
    foreach my $item ( @items ) {
        my $item_url = $item->url;
        
        # http://www.suning.com/emall/prd_10052_10051_-7_3782650_.html
        if ( $item_url =~ m{prd_(\d+)_(\d+)_-(?:\d+)_(\d+)_\.html} ) {
            my $store_id   = $1;
            my $catalog_id = $2;
            my $product_id = $3;

            $item->extra->{store_id}   = $store_id;
            $item->extra->{catalog_id} = $catalog_id;
            $item->extra->{product_id} = $product_id;
            
            my $price_url = "http://www.suning.com/emall/SNProductStatusView?storeId=$store_id&catalogId=$catalog_id&productId=$product_id&cityId=9173&_=" . rand;
            push @coros,
            async {
                my $guard = $sem->guard;
                my $json_headers = $self->json_headers;
                $json_headers->{Referer} = $item_url;

                http_get $price_url,
                headers => $json_headers,
                Coro::rouse_cb;
                
                my ( $body, $hdr ) = Coro::rouse_wait;
                
		my $header = HTTP::Headers->new('content-encoding' => "gzip, deflate", 'content-type' => 'text/html');
		my $mess = HTTP::Message->new( $header, $body );
                my $content = $mess->decoded_content(charset => 'utf-8');

                if ( $content =~ m{"promotionPrice":"(.+?)"} ) {
                    if ( my $price = $1 ) {
                        $item->price($price);
                    }
                } else {
                    $item->available('out of stock');
                }

                my ($sales_org, $dept_no, $vendor);
                if ( $content =~ m{"salesOrg":"(\d+)"} ) {
                    $item->extra->{sales_org} = $1;
                }

                if ( $content =~ m{"deptNo":"(\d+)"} ) {
                    $item->extra->{dept_no} = $1;
                }

                if ( $content =~ m{"vendor":"(\d+)"} ) {
                    $item->extra->{vendor} = $1;
                }
            };
        }
    }

    $_->join foreach ( @coros );
}

sub get_stock {
    my $self  = shift;
    my @items = @_;

    my $sem = Coro::Semaphore->new(30);
    
    my @coros;
    foreach my $item ( @items ) {
	if ($item->available eq 'out of stock') {
	    debug_item($item);
	    $self->add_item($item);
	    next;
	}

        my $item_url = $item->url;

        my ($sales_org, $dept_no, $vendor, $part_num, $store_id, $catalog_id, $product_id) = ($item->extra->{sales_org}, $item->extra->{dept_no}, $item->extra->{vendor}, $item->extra->{part_num}, $item->extra->{store_id}, $item->extra->{catalog_id}, $item->extra->{product_id});
        my $stock_url = "http://www.suning.com/emall/SNProductSaleView?storeId=$store_id&catalogId=$catalog_id&productId=$product_id&salesOrg=$sales_org&deptNo=$dept_no&vendor=$vendor&partNumber=$part_num&cityId=9173&districtId=&_=" . rand;

	push @coros,
	async {
	    my $guard = $sem->guard;
            my $json_headers = $self->json_headers;
            $json_headers->{Referer} = $item_url;
            
            http_get $stock_url,
            headers => $json_headers,
            Coro::rouse_cb;
            
            my ( $body, $hdr ) = Coro::rouse_wait;

            my $header = HTTP::Headers->new('content-encoding' => "gzip, deflate", 'content-type' => 'text/html');
            my $mess = HTTP::Message->new( $header, $body );
            my $content = $mess->decoded_content(charset => 'utf-8');
            
            if ( $content =~ m{"inventoryFlag":"(\d+)"} ) {
                unless ( $1 ) {
                    $item->available('out of stock');
                }
            } else {
                $item->available('out of stock');
            }
	    
	    debug_item($item);
	    $self->add_item($item);
	};
    }

    $_->join foreach ( @coros );        
    
    return;
}

__PACKAGE__->meta->make_immutable;

1;




