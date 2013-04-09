package Asthma::Spider::YiXunMobile;

use Moose;
extends 'Asthma::Spider';

use utf8;
use Asthma::Item;
use Asthma::Debug;
use HTML::TreeBuilder;
use Data::Dumper;
use Coro;
use AnyEvent::HTTP;
use HTTP::Headers;
use HTTP::Message;

sub BUILD {
    my $self = shift;
    $self->site_id(105);
    $self->start_url('http://www.51buy.com/portal.html');
}

sub run {
    my $self = shift;
    $self->start_find_urls;

    $self->storage->redis_db->execute('SET', $self->item_url_id, 0);
    $self->storage->redis_db->execute('ZREMRANGEBYRANK', $self->item_url_link, 0, -1);

    my $loop = 0;
    my $run = 1;
    while ( $run ) {
        last unless $self->find_urls($loop++);
    }

    $loop = 0;
    $run = 1;
    while ( $run ) {
        last unless $self->parse_item_urls($loop++);
    }
}

sub start_find_urls {
    my $self = shift;
    my $resp = $self->ua->get($self->start_url);

    $self->storage->redis_db->execute('SET', $self->list_url_id, 0);  # set list url id init value to '0'
    $self->storage->redis_db->execute('ZREMRANGEBYRANK', $self->list_url_link, 0, -1);  # remove all url save in list url

    if ( my $content = $resp->decoded_content ) {
        my $tree = HTML::TreeBuilder->new_from_content($content);
        if ( my $div = $tree->look_down('id', 'protal_list') ) {
            foreach my $dd ( $div->look_down(_tag => 'dd') ) {
                foreach my $link ( $dd->look_down(_tag => 'a') ) {
                    my $url = $link->attr("href");
                    $self->storage->redis_db->execute('INCR', $self->list_url_id);
                    my $id = $self->storage->redis_db->execute('GET', $self->list_url_id);
                    if ( $self->storage->redis_db->execute('ZADD', $self->list_url_link, $id, $url) ) {
                        debug("add list url $url success");
                    } else {
                        debug("add list url $url failed");
                    }
                }
            }
        }
	$tree->delete;
    }
}

sub find_urls {
    my ($self, $loop) = @_;

    my $start = $loop*100;
    my $end   = $start + 99;
    
    debug("start: $start, end: $end");

    my $urls = $self->storage->redis_db->execute('ZRANGE', $self->list_url_link, $start, $end);

    if ( @$urls ) {
        my $sem = Coro::Semaphore->new(100);
        my @coros;

        foreach my $url ( @$urls ) {
            push @coros,
            async {
                my $guard = $sem->guard;

                http_get $url,
                headers => $self->headers,
                Coro::rouse_cb;

                my ($body, $hdr) = Coro::rouse_wait;

                debug("process $hdr->{URL}");

                my $header = HTTP::Headers->new('content-encoding' => 'gzip, deflate', 'content-type' => 'text/html');
                my $mess = HTTP::Message->new( $header, $body );
                
                if ( my $content = $mess->decoded_content(charset => 'gbk') ) {
                    my $tree = HTML::TreeBuilder->new_from_content($content);
                    if ( my $ul = $tree->look_down(_tag => 'ul', class => 'list_goods') ) {
                        foreach my $li ( $ul->look_down(_tag => 'li', class => 'item_list') ) {
                            my $item_url = $li->look_down(_tag => 'a', class => 'link_pic')->attr('href');
                            $self->storage->redis_db->execute('INCR', $self->item_url_id);
                            my $id = $self->storage->redis_db->execute('GET', $self->item_url_id);
                            if ( $self->storage->redis_db->execute('ZADD', $self->item_url_link, $id, $item_url) ) {
                                debug("add item url $item_url success");
                            } else {
                                debug("add item url $item_url failed");
                            }
                        }
                    }


                    if ( $tree->look_down('class', 'page-next') ) {
                        if ( my $page_url = $tree->look_down('class', 'page-next')->attr('href') ) {
                            $page_url =~ s{#.*}{};
                            $self->storage->redis_db->execute('INCR', $self->list_url_id);
                            my $id = $self->storage->redis_db->execute('GET', $self->list_url_id);
                            if ( $self->storage->redis_db->execute('ZADD', $self->list_url_link, $id, $page_url) ) {
                                debug("add next page_url $page_url success");
                            } else {
                                debug("add next page_url $page_url failed");
                            }
                        }
                    }
		    $tree->delete;
                }
            }
        }

        $_->join foreach ( @coros );

        return 1;
    } else {
        return 0;
    }
}

sub parse_item_urls {
    my ($self, $loop) = @_;
    my $start = 100*$loop;
    my $end   = $start+99;
    debug("start: $start, end: $end");

    my $urls = $self->storage->redis_db->execute('ZRANGE', $self->item_url_link, $start, $end);
    
    if ( @$urls ) {
        my $sem = Coro::Semaphore->new(100);
        my @coros;

        foreach my $url ( @$urls ) {
            push @coros,
            async {
                my $guard = $sem->guard;

                http_get $url,
                headers => $self->headers,
                Coro::rouse_cb;

                my ($body, $hdr) = Coro::rouse_wait;

                debug("process $hdr->{URL}");

                my $header = HTTP::Headers->new('content-encoding' => 'gzip, deflate', 'content-type' => 'text/html');
                my $mess = HTTP::Message->new( $header, $body );

                if ( my $content = $mess->decoded_content() ) {
                    my $item = Asthma::Item->new();

                    if ( $url =~ m{item-(\d+)\.html} ) {
                        $item->url($url);
                        my $sku = $1;
                        $item->sku($sku);
                    }

                    if ( $content =~ m{var\s+itemInfo\s+=\s+\{.*?"name"\s*:\s*"(.+?)"} ) {
                        my $title = $1;
                        $item->title($title);
                    }

                    my $api_url = "http://item.51buy.com/json.php?mod=item&act=getdynamiciteminfo&pid=" . $item->sku . "&whid=1&prid=1&_=" . time;
                    my $resp = $self->{ua}->get($api_url);
                    my $api_content = $resp->decoded_content;
                    
                    if ( $api_content =~ m{"price":"([\d.]+)} ) {
                        my $price = $1;
                        $item->price($price);
                    }

                    if ( $api_content =~ m{"stock_show":"(.+?)"} ) {
                        my $stock = $1;
                        if ( $stock !~ m{有货} ) {
                            $item->available('out of stock');
                        }
                    }

                    debug_item($item);
                    $self->add_item($item);
                }
            }
        }

        $_->join foreach ( @coros );

        return 1;
    } else {
        return 0;
    }    

}

__PACKAGE__->meta->make_immutable;

1;


