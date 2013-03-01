package Asthma::Storage;
use Moose;
use Redis;
use namespace::autoclean;

has 'redis' => (is => 'rw', isa => 'Redis', lazy_build => 1);

sub _build_redis {
    my $self = shift;
    my $redis = Redis->new;
    return $redis;
}

__PACKAGE__->meta->make_immutable;

1;
