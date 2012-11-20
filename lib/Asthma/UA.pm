package Asthma::UA;

use Moose::Role;
use namespace::autoclean;
use Class::Load 'load_class';

has 'ua_class' => (is => 'rw', isa => 'Str', default => 'LWP::UserAgent');

has 'ua_args'  => (is => 'rw', isa => 'HashRef', default => sub { {
    agent   => 'Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 6.0; Trident/5.0)',
} });

has 'ua' => (
    is => 'rw',
    lazy_build => 1
);

sub _build_ua {
    my $self = shift;
    my $class = $self->ua_class;
    load_class($class) or die;
    return $class->new( %{$self->ua_args} );
}

1;
