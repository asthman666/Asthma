package Asthma::Discovery::51Buy;
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
    $self->site_id(105);
    $self->start_url('http://www.51buy.com/portal.html');
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

    if ( my $content = $resp->decoded_content ) {
        my $tree = HTML::TreeBuilder->new_from_content($content);
        if ( my $div = $tree->look_down('id', 'protal_list') ) {
            foreach my $dd ( $div->look_down(_tag => 'dd') ) {
                foreach my $link ( $dd->look_down(_tag => 'a') ) {
                    if ( my $url = $link->attr("href") ) {
			my $md5_link = md5_base64($url);
			my $now = "now()";

			my $u = $self->storage->mysql->resultset($self->site_id . 'ListUrls')->find_or_new({ link => $url,
													     md5_link => $md5_link,
													     dt_created => \$now,
													     dt_updated => \$now,
													   }, {key => 'md5_link'});
			if ( ! $u->in_storage ) {
			    debug("url $url with md5 $md5_link need to be added");
			    $u->insert;
			} else {
			    debug("url $url with md5 $md5_link and list_url_id " . $u->list_url_id . " exists");
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

    my $rows = 100;
    my $urls = [$self->storage->mysql->resultset($self->site_id . 'ListUrls')->search(
		    undef,
		    {
			offset => $start,
			rows   => $rows,
		    })];


    my $rs = $self->storage->mysql->resultset($self->site_id . 'ListUrls')->search();
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

                debug("process $hdr->{URL}");

                my $header = HTTP::Headers->new('content-encoding' => 'gzip, deflate', 'content-type' => 'text/html');
                #my $header = HTTP::Headers->new('content-type' => 'text/html');
                my $mess = HTTP::Message->new( $header, $body );
                
                if ( my $content = $mess->decoded_content(charset => 'gbk') ) {
                    my $tree = HTML::TreeBuilder->new_from_content($content);
                    if ( my $ul = $tree->look_down(_tag => 'ul', class => 'list_goods') ) {
                        foreach my $li ( $ul->look_down(_tag => 'li', class => 'item_list') ) {
                            
                            if ( my $item_url = $li->look_down(_tag => 'a', class => 'link_pic')->attr('href') ) {
				my $md5_link = md5_base64($item_url);
				my $now = "now()";

				my $u = $self->storage->mysql->resultset($self->site_id . 'ItemUrls')->find_or_new({ link => $item_url,
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


                    if ( $tree->look_down('class', 'page-next') ) {
                        if ( my $page_url = $tree->look_down('class', 'page-next')->attr('href') ) {
                            $page_url =~ s{#.*}{};
			    
			    my $md5_link = md5_base64($page_url);
			    my $now = "now()";

			    my $u = $self->storage->mysql->resultset($self->site_id . 'ListUrls')->find_or_new({ link => $page_url,
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


