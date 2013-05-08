package Asthma::Storage;
use Moose;
use Redis;
use RedisDB;
use Asthma::Schema;
use namespace::autoclean;

has 'mysql' => (is => 'rw', isa => 'Asthma::Schema', lazy_build => 1);
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

sub _build_mysql {
    my $self = shift;
    return Asthma::Schema->connect('dbi:mysql:asthma:mysql_enable_utf8=1', 'foo', 'bar');
}

__PACKAGE__->meta->make_immutable;

1;
