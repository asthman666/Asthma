package Asthma::Discovery;
use Moose;
use Asthma::Storage;

with 'Asthma::UA';

has 'site_id' => (is => 'rw', isa => 'Int');

has 'depth' => (is => 'rw', isa => 'Int', default => 0);

has 'start_url' => (is => 'rw', isa => 'Str');
has 'start_urls' => (is => 'rw', isa => 'ArrayRef[Str]', default => sub { [] });

has 'storage' => (is => 'rw', lazy_build => 1);

has 'list_url_id' => (is => 'rw', isa => 'Str', lazy => 1, default => sub { return $_[0]->site_id . ':list_url:id'});
has 'list_url_link' => (is => 'rw', isa => 'Str', lazy => 1, default => sub { return $_[0]->site_id . ':list_url:link'});

has 'item_url_id' => (is => 'rw', isa => 'Str', lazy => 1, default => sub { return $_[0]->site_id . ':item_url:id'});
has 'item_url_link' => (is => 'rw', isa => 'Str', lazy => 1, default => sub { return $_[0]->site_id . ':item_url:link'});

sub _build_storage {
    my $self = shift;
    my $storage = Asthma::Storage->new;
    return $storage;
}

__PACKAGE__->meta->make_immutable;

1;


