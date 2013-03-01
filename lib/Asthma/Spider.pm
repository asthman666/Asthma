package Asthma::Spider;
use Moose;
use Asthma::Storage;

with 'Asthma::UA';
with 'Asthma::File';

has 'urls' => (is => 'rw', isa => 'ArrayRef[Str]', default => sub { [] });
has 'p_urls' => (is => 'rw', isa => 'ArrayRef[Str]', default => sub { [] });
has 'chunk_num' => (is => 'rw', isa => 'Int', default => 0);
has 'site_id' => (is => 'rw', isa => 'Int');
has 'start_url' => (is => 'rw', isa => 'Str');
has 'start_urls' => (is => 'rw', isa => 'ArrayRef[Str]', default => sub { [] });
has 'storage' => (is => 'rw', lazy_build => 1);

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

