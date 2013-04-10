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

    my $loop = 0;
    my $run = 1;
    while ( $run ) {
        last unless $self->parse_item_urls($loop++);
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



