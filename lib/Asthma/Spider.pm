package Asthma::Spider;
use Moose;

with 'Asthma::UA';
with 'Asthma::File';

has 'urls' => (is => 'rw', isa => 'ArrayRef[Str]', default => sub { [] });

sub add_item {
    my $self = shift;
    my $item = shift;
    push @{$self->{items}}, $item;

    $self->wf($self->{items});

    $self->clean_item;
}

sub clean_item {
    my $self = shift;
    delete $self->{items};
}

__PACKAGE__->meta->make_immutable;

1;
