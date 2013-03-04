package Asthma::Spider;
use Moose;
use Asthma::Storage;

with 'Asthma::UA';
with 'Asthma::File';

has 'depth' => (is => 'rw', isa => 'Int', default => 0);
has 'urls' => (is => 'rw', isa => 'ArrayRef[Str]', default => sub { [] });
has 'p_urls' => (is => 'rw', isa => 'ArrayRef[Str]', default => sub { [] });
has 'chunk_num' => (is => 'rw', isa => 'Int', default => 0);
has 'site_id' => (is => 'rw', isa => 'Int');
has 'start_url' => (is => 'rw', isa => 'Str');
has 'start_urls' => (is => 'rw', isa => 'ArrayRef[Str]', default => sub { [] });
has 'storage' => (is => 'rw', lazy_build => 1);
has 'headers' => (is => 'rw', isa => 'HashRef', 
		  default => sub { 
		      {
			  "user-agent" => "Mozilla/5.0 (Windows NT 6.1; rv:17.0) Gecko/20100101 Firefox/17.0",
			  "Accept-Encoding" => "gzip, deflate",
			  'Accept-Language' => "zh-cn,zh;q=0.8,en-us;q=0.5,en;q=0.3",
			  'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
		      } 
		  });

sub _build_storage {
    my $self = shift;
    my $storage = Asthma::Storage->new;
    return $storage;
}

sub add_item {
    my $self = shift;
    my $item = shift;

    return unless $item->sku;

    push @{$self->{items}}, $item;

    if ( $self->{items} && @{$self->{items}} >= 100 ) {
    	$self->wf;  # write to file
	my $cn = $self->chunk_num;
	$self->clean_item;
	$self->chunk_num(++$cn);
    }
}

sub clean_item {
    my $self = shift;
    delete $self->{items};
}

__PACKAGE__->meta->make_immutable;

1;

