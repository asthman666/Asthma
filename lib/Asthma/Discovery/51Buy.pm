package Asthma::Discovery::51Buy;
use Moose;
extends 'Asthma::Discovery';

use Coro;
use AnyEvent::HTTP;
use HTTP::Headers;
use HTTP::Message;
use Asthma::Debug;
use HTML::TreeBuilder;
use Data::Dumper;

sub BUILD {
    my $self = shift;
    $self->site_id(105);
    $self->start_url('http://www.51buy.com/portal.html');
}

sub run {
    my $self = shift;

    $self->storage->redis_db->execute('SET', $self->item_url_id, 0);
    $self->storage->redis_db->execute('ZREMRANGEBYRANK', $self->item_url_link, 0, -1);

    $self->storage->redis_db->execute('SET', $self->list_url_id, 0);  # set list url id init value to '0'
    $self->storage->redis_db->execute('ZREMRANGEBYRANK', $self->list_url_link, 0, -1);  # remove all url save in list url

    $self->start_find_urls;

    my $run = 1;

    my $start = 0;
    while ( $run ) {
        last unless $start = $self->find_urls($start);
    }
}

sub start_find_urls {
    my $self = shift;
    my $resp = $self->ua->get($self->start_url);

    if ( my $content = $resp->decoded_content ) {
        my $tree = HTML::TreeBuilder->new_from_content($content);
        if ( my $div = $tree->look_down('id', 'protal_list') ) {
            foreach my $dd ( $div->look_down(_tag => 'dd') ) {
                foreach my $link ( $dd->look_down(_tag => 'a') ) {
                    my $url = $link->attr("href");
                    if ( my $score = $self->storage->redis_db->execute('ZSCORE', $self->list_url_link, $url) ) {
                        debug("$url exists in key '" . $self->list_url_link . "' with score $score");
                    } else {
                        $self->storage->redis_db->execute('INCR', $self->list_url_id);
                        my $id = $self->storage->redis_db->execute('GET', $self->list_url_id);
                        if ( $self->storage->redis_db->execute('ZADD', $self->list_url_link, $id, $url) ) {
                            debug("add score: $id, url: $url to key: '" . $self->list_url_link . "' success");
                        } else {
                            debug("add score: $id, url: $url to key: '" . $self->list_url_link . "' failed");
                        }
                    }
                }
            }
        }
	$tree->delete;
    }
}

sub find_urls {
    my ($self, $start) = @_;

    my $end = $start + 99;

    my $count = $self->storage->redis_db->execute('ZCARD', $self->list_url_link);
    if ( $count < $end ) {
        $end = $count - 1;
    }

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
                #my $header = HTTP::Headers->new('content-type' => 'text/html');
                my $mess = HTTP::Message->new( $header, $body );
                
                if ( my $content = $mess->decoded_content(charset => 'gbk') ) {
                    my $tree = HTML::TreeBuilder->new_from_content($content);
                    if ( my $ul = $tree->look_down(_tag => 'ul', class => 'list_goods') ) {
                        foreach my $li ( $ul->look_down(_tag => 'li', class => 'item_list') ) {
                            
                            my $item_url = $li->look_down(_tag => 'a', class => 'link_pic')->attr('href');

                            if ( my $score = $self->storage->redis_db->execute('ZSCORE', $self->item_url_link, $item_url) ) {
                                debug("$item_url exists in key '" . $self->item_url_link . "' with score $score");
                            } else {
                                $self->storage->redis_db->execute('INCR', $self->item_url_id);
                                my $id = $self->storage->redis_db->execute('GET', $self->item_url_id);
                                if ( $self->storage->redis_db->execute('ZADD', $self->item_url_link, $id, $item_url) ) {
                                    debug("add score: $id, url: $item_url to key: '" . $self->item_url_link . "' success");
                                } else {
                                    debug("add score: $id, url: $item_url to key: '" . $self->item_url_link . "' failed");
                                }
                            }

                        }
                    }


                    if ( $tree->look_down('class', 'page-next') ) {
                        if ( my $page_url = $tree->look_down('class', 'page-next')->attr('href') ) {
                            $page_url =~ s{#.*}{};
                            
                            if ( my $score = $self->storage->redis_db->execute('ZSCORE', $self->list_url_link, $page_url) ) {
                                debug("$page_url exists in key '" . $self->list_url_link . "' with score $score");
                            } else {
                                $self->storage->redis_db->execute('INCR', $self->list_url_id);
                                my $id = $self->storage->redis_db->execute('GET', $self->list_url_id);
                                if ( $self->storage->redis_db->execute('ZADD', $self->list_url_link, $id, $page_url) ) {
                                    debug("add score: $id, url: $page_url to key: '" . $self->list_url_link . "' success");
                                } else {
                                    debug("add score: $id, url: $page_url to key: '" . $self->list_url_link . "' failed");
                                }
                            }                            
                        }
                    }
		    $tree->delete;
                }
            }
        }

        $_->join foreach ( @coros );

        return $end + 1;
    } else {
        return 0;
    }
}

__PACKAGE__->meta->make_immutable;

1;


