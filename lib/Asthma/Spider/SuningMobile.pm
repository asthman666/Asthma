package Asthma::Spider::SuningMobile;
use Moose;
extends 'Asthma::Spider';

use utf8;
use Asthma::Item;
use Asthma::Debug;
use HTML::TreeBuilder;
use AnyEvent;
use AnyEvent::HTTP;
use HTTP::Headers;
use HTTP::Message;
use Data::Dumper;

has 'json_ua' => (is => 'rw', isa => 'LWP::UserAgent', lazy_build => 1);

sub _build_json_ua {
    my $ua = LWP::UserAgent->new();
    $ua->agent('Mozilla/5.0 (Windows NT 5.1; rv:18.0) Gecko/20100101 Firefox/18.0');
    $ua->default_header('Accept' => 'application/json, text/javascript, */*');	
    $ua->default_header('Accept-Language' => 'zh-cn,zh;q=0.8,en-us;q=0.5,en;q=0.3');	
    $ua->default_header('Accept-Encoding' => 'gzip, deflate');
    $ua->default_header('X-Requested-With' => 'XMLHttpRequest');
    return $ua;
}

sub BUILD {
    my $self = shift;
    $self->site_id(103);
    $self->start_url('http://search.suning.com/emall/strd.do?ci=20006');
}

sub run {
    my $self = shift;

    my $start_url = $self->start_url;

    foreach ( 0..20 ) {
        my $url = $start_url;
        $url .= "&cp=$_";
        my $resp = $self->ua->get($url);        
        $self->find($resp);
    }
}

sub find {
    my $self = shift;
    my $resp = shift;
    return unless $resp;
    
    debug("process: " . $resp->request->uri->as_string);

    my @plinks;

    if ( my $content = $resp->decoded_content ) {
        my $tree = HTML::TreeBuilder->new_from_content($content);
        
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

    if ( @plinks ) {
	my $cv = AnyEvent->condvar;

	foreach my $url ( @plinks ) {
	    my $sku;
	    if ( $url =~ m{([^/]+)\.html} ) {
		$sku = $1;
	    }

	    $cv->begin;
	    http_get $url, 
	    headers => {
		"user-agent" => "Mozilla/5.0 (Windows NT 6.1; rv:17.0) Gecko/20100101 Firefox/17.0",
		"Accept-Encoding" => "gzip, deflate",
		'Accept-Language' => "zh-cn,zh;q=0.8,en-us;q=0.5,en;q=0.3",
		'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
	    },

	    sub {
		my ( $body, $hdr ) = @_;
		
		my $header = HTTP::Headers->new('content-encoding' => "gzip, deflate", 'content-type' => 'text/html');
		my $mess = HTTP::Message->new( $header, $body );
		my $content = $mess->decoded_content(charset => 'utf-8');
		my $item = $self->parse($content);

                # "partNumber":"000000000103329145"
                my $part_num;
                if ( $content =~ m{"partNumber":"(\d+)"}) {
                    $part_num = $1;
                }

		$item->sku($sku);
		$item->url($url);

                $self->get_stock($item, $part_num);
                
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
            if ( my $title_span = $sku_tree->look_down(_tag => 'h1')->look_down(_tag => 'span') ) {
                if ( my @cons = $title_span->content_list ) {
                    if ( my $title = $cons[0] ) {
                        $item->title($title);
                    }
                }
            }
	}

	#if ( $content =~ m{currPrice\s*=(.+?)&} ) {
        #    my $price = $1;
        #    $item->price($price);
        #} else {
	#    $item->available('out of stock');
	#}

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

sub get_stock {
    my $self = shift;
    my $item = shift;
    my $part_num = shift;
    return unless $item;
    return unless $item->url;

    my $item_url = $item->url;
    
    # http://www.suning.com/emall/prd_10052_10051_-7_3782650_.html
    if ( $item_url =~ m{prd_(\d+)_(\d+)_-(?:\d+)_(\d+)_\.html} ) {
        my $store_id   = $1;
        my $catalog_id = $2;
        my $product_id = $3;
        my $url = "http://www.suning.com/emall/SNProductStatusView?storeId=$store_id&catalogId=$catalog_id&productId=$product_id&cityId=9173&_=" . rand;
        #debug("url: $url");
        # { "salesOrg":"5016", "deptNo":"0001", "vendor":"0010035508", "promotionPrice":"5129.00", "itemPrice":"", "netPrice":"5129.00" } 

        $self->json_ua->default_header('Referer' => $item_url);

        my $resp = $self->json_ua->get($url);
        my $content = $resp->decoded_content;

        my $max_try = 3;
        while ( $content =~ m{title} && $max_try ) {
            # retry
            debug("get resp for price: " . Dumper $resp);
            debug("get content for price: $content");
            debug("retry " . (4-$max_try) . " for price: $url");
            $resp = $self->json_ua->get($url);
            $content = $resp->decoded_content;
            $max_try--;
        }

        #debug $content;

        if ( $content =~ m{"promotionPrice":"(.+?)"} ) {
            if ( my $price = $1 ) {
                $item->price($price);
            }
        }

        my ($sales_org, $dept_no, $vendor);
        if ( $content =~ m{"salesOrg":"(\d+)"} ) {
            $sales_org = $1;
        }

        if ( $content =~ m{"deptNo":"(\d+)"} ) {
            $dept_no = $1;
        }

        if ( $content =~ m{"vendor":"(\d+)"} ) {
            $vendor = $1;
        }

        # http://www.suning.com/emall/SNProductSaleView?storeId=10052&catalogId=10051&productId=2052998&salesOrg=5016&deptNo=0001&vendor=0010037230&partNumber=000000000102535623&cityId=9173&districtId=&_=1359689905024
        if ( $sales_org && $dept_no && $vendor && $part_num ) {
            my $url2 = "http://www.suning.com/emall/SNProductSaleView?storeId=$store_id&catalogId=$catalog_id&productId=$product_id&salesOrg=$sales_org&deptNo=$dept_no&vendor=$vendor&partNumber=$part_num&cityId=9173&districtId=&_=" . rand;
            #debug("url2: $url2");
            my $resp2 = $self->json_ua->get($url2);
            my $content2 = $resp2->decoded_content;
            
            my $max_try2 = 3;
            while ( $content2 !~ m{inventoryFlag} && $max_try2 ) {
                debug("get resp for stock: " . Dumper $resp2);
                debug("get content for stock: $content2");
                debug("retry " . (4-$max_try2) . " for stock: $url2");
                $resp2 = $self->json_ua->get($url2);
                $content2 = $resp2->decoded_content;
                $max_try2--;
            }

            if ( $content2 =~ m{"inventoryFlag":"(\d+)"} ) {
                unless ( $1 ) {
                    $item->available('out of stock');
                }
            } else {
                $item->available('out of stock');
            }
        }
	
	# NOTE: no price, no stock for suning
	unless ( $item->price ) {
	    $item->available('out of stock');
	}
    }
}

__PACKAGE__->meta->make_immutable;

1;



