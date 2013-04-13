package Asthma::Spider::51Buy;

use Moose;
extends 'Asthma::Spider';

use utf8;
use Asthma::Item;
use Asthma::Debug;
use Data::Dumper;
use Coro;
use AnyEvent::HTTP;
use HTTP::Headers;
use HTTP::Message;

sub BUILD {
    my $self = shift;
    $self->site_id(105);
}

sub run {
    my $self = shift;

    my $page = 1;
    my $run = 1;
    while ( $run ) {
        last unless $self->parse_item_urls($page++);
    }
}

sub parse_item_urls {
    my ($self, $page) = @_;
    my $rows = 100;
    debug("page: $page, rows: $rows");

    my $urls = [$self->storage->mysql->resultset($self->site_id . 'ItemUrls')->search(
		    undef,
		    {
			page => $page,
			rows => $rows,
		    })];

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
                
                my $header = HTTP::Headers->new('content-encoding' => 'gzip, deflate', 'content-type' => 'text/html');
                #my $header = HTTP::Headers->new('content-type' => 'text/html');
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
                    my $resp = $self->ua->get($api_url);
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



