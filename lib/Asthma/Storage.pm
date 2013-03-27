package Asthma::Storage;
use Moose;
use Redis;
use RedisDB;
use namespace::autoclean;

has 'redis' => (is => 'rw', isa => 'Redis', lazy_build => 1);
has 'redis_db' => (is => 'rw', isa => 'RedisDB', lazy_build => 1);

sub _build_redis {
    my $self = shift;
    my $redis = Redis->new(reconnect => 60);
    return $redis;
}

sub _build_redis_db {
    my $self = shift;
    my $redis_db = RedisDB->new();
    return $redis_db;
}

__PACKAGE__->meta->make_immutable;

1;
