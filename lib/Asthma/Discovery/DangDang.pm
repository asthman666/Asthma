package Asthma::Discovery::DangDang;
use Moose;
extends 'Asthma::Discovery';

use Coro;
use AnyEvent::HTTP;
use HTTP::Headers;
use HTTP::Message;
use Asthma::Debug;
use HTML::TreeBuilder;
use Digest::MD5 qw(md5_base64);
use Data::Dumper;

sub BUILD {
    my $self = shift;
    $self->site_id(101);
    $self->start_url('http://category.dangdang.com/');
}

sub run {
    my $self = shift;

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
    if ( $resp->is_success ) {
        if ( my $content = $resp->decoded_content ) {
            my $tree = HTML::TreeBuilder->new_from_content($content);
            foreach my $div ( $tree->look_down(sub { $_[0]->attr('id') && ($_[0]->attr('id') eq 'phone' || $_[0]->attr('id') eq 'computer' || $_[0]->attr('id') eq 'electric' || $_[0]->attr('id') eq 'car' || $_[0]->attr('id') eq 'mother') }) ) {
                foreach my $li ($div->look_down(_tag => 'li')) {
                    foreach my $ah ( $li->look_down(_tag => 'a', sub { !($_[0]->attr('class') && $_[0]->attr('class') eq 'title') }) ) {
                        my $link = $ah->attr('href');

                        # next if ( $link ne 'http://category.dangdang.com/all/?category_id=4006498' );
                        
                        my $md5_link = md5_base64($link);
                        my $now = "now()";
                        my $u = $self->storage->mysql->resultset($self->site_id . 'ListUrl')->find_or_new({ link => $link,
                                                                                                            md5_link => $md5_link,
                                                                                                            dt_created => \$now,
                                                                                                            dt_updated => \$now,
                                                                                                          }, {key => 'md5_link'});
                        if ( ! $u->in_storage ) {
                            debug("link $link with md5 $md5_link need to be added");
                            $u->insert;
                        } else {
                            debug("link $link with md5 $md5_link and list_url_id " . $u->list_url_id . " exists");
                        }
                    }
                }
            }
        }
    } else {
        debug("get start url resp status_line: " . $resp->status_line);
    }
}

sub find_urls {
    my ($self, $start) = @_;

    my $rows = 100;
    my $urls = [$self->storage->mysql->resultset($self->site_id . 'ListUrl')->search(
		    undef,
		    {
			offset => $start,
			rows   => $rows,
		    })];


    my $rs = $self->storage->mysql->resultset($self->site_id . 'ListUrl')->search();
    my $count = $rs->count;
    
    if ( $count < ($start+$rows) ) {
	$rows = $count - $start;
    }

    debug("start: $start, rows: $rows");

    if ( @$urls ) {
        my $sem = Coro::Semaphore->new(100);
        my @coros;

        foreach my $url_object ( @$urls ) {
	    my $url = $url_object->link;
            push @coros,
            async {
                my $guard = $sem->guard;

                http_get $url,
                headers => $self->headers,
                Coro::rouse_cb;

                my ($body, $hdr) = Coro::rouse_wait;

		debug("$hdr->{Status} $hdr->{Reason} $hdr->{URL}");

                my $header = HTTP::Headers->new('content-encoding' => 'gzip, deflate', 'content-type' => 'text/html');
                my $mess = HTTP::Message->new( $header, $body );
                
                if ( my $content = $mess->decoded_content(charset => 'gbk') ) {
                    my $tree = HTML::TreeBuilder->new_from_content($content);

                    if ( my $plist = $tree->look_down('class', 'shoplist') ) {
                        foreach my $li ( $plist->look_down(_tag => 'li', name => 'lb') ) {
                            if ( my $ah = $li->look_down(_tag => 'a', class => 'pic') ) {
                                if ( my $item_url = $ah->attr('href') ) {
                                    my $md5_link = md5_base64($item_url);
                                    my $now = "now()";
                                    my $u = $self->storage->mysql->resultset($self->site_id . 'ItemUrl')->find_or_new({ link => $item_url,
                                                                                                                        md5_link => $md5_link,
                                                                                                                        dt_created => \$now,
                                                                                                                        dt_updated => \$now,
                                                                                                                      }, {key => 'md5_link'});
                                    if ( ! $u->in_storage ) {
                                        debug("url $item_url with md5 $md5_link need to be added");
                                        $u->insert;
                                    } else {
                                        debug("url $item_url with md5 $md5_link and item_url_id " . $u->item_url_id . " exists");
                                    }
                                }
                            }
                        }
                    }


                    if ( my $next = $tree->look_down(class => 'next') ) {
                        if ( my $ah = $next->look_down(_tag => 'a') ) {
                            if ( my $page_url = $ah->attr("href") ) {
                                $page_url = URI->new_abs($page_url, $url)->as_string;

                                my $md5_link = md5_base64($page_url);
                                my $now = "now()";
                                my $u = $self->storage->mysql->resultset($self->site_id . 'ListUrl')->find_or_new({ link => $page_url,
                                                                                                                    md5_link => $md5_link,
                                                                                                                    dt_created => \$now,
                                                                                                                    dt_updated => \$now,
                                                                                                                  }, {key => 'md5_link'});
                                if ( ! $u->in_storage ) {
                                    debug("url $page_url with md5 $md5_link need to be added");
                                    $u->insert;
                                } else {
                                    debug("url $page_url with md5 $md5_link and list_url_id " . $u->list_url_id . " exists");
                                }
                            }
                        }
                    }
                    
		    $tree->delete;
                }
            }
        }

        $_->join foreach ( @coros );

        return $start+$rows;
    } else {
        return 0;
    }
}

__PACKAGE__->meta->make_immutable;

1;





