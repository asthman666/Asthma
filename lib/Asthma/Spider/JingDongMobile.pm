package Asthma::Spider::JingDongMobile;
use Moose;
extends 'Asthma::Spider';

use utf8;
use Asthma::Item;
use Asthma::Debug;
use HTML::TreeBuilder;
use URI;
use Coro;
use Coro::Semaphore;
use AnyEvent;
use AnyEvent::HTTP;
use HTTP::Headers;
use HTTP::Message;

sub BUILD {
    my $self = shift;
    $self->site_id(102);
    $self->start_urls(['http://www.360buy.com/products/652-653-655.html',    # 手机
		       'http://www.360buy.com/products/670-671-672.html',    # 笔记本
		       'http://www.360buy.com/products/670-671-6864.html',   # 超级本
		       'http://www.360buy.com/products/670-671-1105.html',   # 上网本
		       'http://www.360buy.com/products/670-671-2694.html',   # 平板电脑
		      ]);
}

sub run {
    my $self = shift;

    @{$self->urls} = @{$self->start_urls};

    my $i;
    while ( 1 ) {
	$i++;
	my $time = time;
	$self->ifind;
	$self->ido;
	debug("loop $i done, cost " . (time - $time));
	last unless @{$self->urls};
        last if $self->depth && $i >= $self->depth;
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
		my $content = $mess->decoded_content(charset => 'gbk');

		if ( my $content = $mess->decoded_content ) {
		    my $tree = HTML::TreeBuilder->new_from_content($content);
		    if ( $tree->look_down('class', 'pagin pagin-m') ) {
			if ( $tree->look_down('class', 'pagin pagin-m')->look_down("class", "next") ) {
			    if ( my $page_url = $tree->look_down('class', 'pagin pagin-m')->look_down("class", "next")->attr("href") ) {
				$page_url = URI->new_abs($page_url, $url)->as_string;
				debug("get next page_url: $page_url");
				push @{$self->urls}, $page_url;
			    }
			}
		    }
		    
		    if ( my $plist = $tree->look_down('id', 'plist') ) {
			if ( my @lis = $plist->look_down(_tag => 'li', sku => qr/\d+/) ) {
			    foreach ( @lis ) {
				my $sku = $_->attr("sku");
				next unless $sku;
				my $url = "http://www.360buy.com/product/$sku.html";
				$self->storage->redis->rpush($self->site_id, $url);
			    }
			}
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

sub ido {
    my $self = shift;
    
    my $sem = Coro::Semaphore->new(30);

    my @items;
    
    my @coros;
    my $run = 1;
    while ( $run ) {
	if ( my $url = $self->storage->redis->lpop($self->site_id) ) {
	    next if $url !~ m{product/(\d+)\.html};
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
		my $content = $mess->decoded_content(charset => 'gbk');
		my $item = $self->parse($content, $sku);
		
		$item->sku($sku);
		$item->url($url);
		push @items, $item;
	    }
	} else {
	    $run = 0;
	}
    }

    $_->join foreach ( @coros );

    # get price
    $self->fprice(@items);

    # get stock
    $self->get_stock(@items);
    
}

sub parse {
    my $self    = shift;
    my $content = shift;
    my $sku     = shift;

    my $item = Asthma::Item->new();
    $item->sku($sku);
    
    if ( $content ) {
	my $sku_tree = HTML::TreeBuilder->new_from_content($content);

	if ( $sku_tree->look_down(_tag => 'h1') ) {
	    $item->title($sku_tree->look_down(_tag => 'h1')->as_trimmed_text);
	}

	if ( $content =~ m{skuidkey\s*:\s*'(.+?)'} ) {
	    $item->extra->{skuidkey} = $1;
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
	my $price_url = "http://jprice.360buy.com/price/np" . $item->sku . "-TRANSACTION-J.html";
	push @coros,
	async {
	    my $guard = $sem->guard;

	    http_get $price_url,
	    headers => $self->headers,
	    Coro::rouse_cb;

	    my ($body, $hdr) = Coro::rouse_wait;
	    debug("$hdr->{Status} $hdr->{Reason} $hdr->{URL}");

	    my $header = HTTP::Headers->new('content-encoding' => "gzip, deflate", 'content-type' => 'text/html');
	    my $mess = HTTP::Message->new( $header, $body );
	    my $content = $mess->decoded_content(charset => 'gbk');

	    if ( $content =~ m/"jdPrice":\{.*?"amount"\s*:(.*?),/is ) {
		my $price = $1;
		$item->price($price);
	    }
	};
    }

    $_->join foreach ( @coros );        
}

sub get_stock {
    my $self  = shift;
    my @items = @_;

    my $sem = Coro::Semaphore->new(30);

    my @coros;
    foreach my $item ( @items ) {
	my $stock_url = "http://price.360buy.com/stocksoa/StockHandler.ashx?callback=getProvinceStockCallback&type=ststock&skuid=" . $item->extra->{skuidkey} . "&provinceid=1&cityid=72&areaid=4137";

	push @coros,
	async {
	    my $guard = $sem->guard;

	    http_get $stock_url,
	    headers => $self->headers,
	    Coro::rouse_cb;

	    my ($body, $hdr) = Coro::rouse_wait;
	    debug("$hdr->{Status} $hdr->{Reason} $hdr->{URL}");

	    if ( $body =~ m{"S":"\d+-(\d+)} ) {
		my $s = $1;
		if ( grep { $s == $_ } (18,34,0) ) {
		    $item->available('out of stock');
		}
	    }
	    
	    debug_item($item);
	    $self->add_item($item);
	};
    }

    $_->join foreach ( @coros );        
    
    my $skuidkey = shift;
    return unless $skuidkey;
    my $url = "http://price.360buy.com/stocksoa/StockHandler.ashx?callback=getProvinceStockCallback&type=ststock&skuid=$skuidkey&provinceid=1&cityid=72&areaid=4137";
    my $resp = $self->ua->get($url);
    my $content = $resp->decoded_content;

    if ( $content =~ m{"S":"\d+-(\d+)} ) {
	my $s = $1;
	if ( grep { $s == $_ } (18,34,0) ) {
	    return 'out of stock';
	}
    }
    
    return;
}

__PACKAGE__->meta->make_immutable;

1;


