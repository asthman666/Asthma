package Asthma::Item;
use Moose;

use Data::Dumper;

has ['title', 'image_url', 'ean', 'sku'] => (is => 'rw', isa => 'Str');
has 'price' => (is => 'rw');
has 'id' => (is => 'rw', isa => 'Str', lazy_build => 1);

before 'ean' => sub {
    if ( my $ean = $_[1] ) {
	$ean =~ s{[^\d]}{}g;
	$_[1] = $ean;
    }
};

before 'price' => sub {
    if ( my $price = $_[1] ) {
	$price =~ s{[^\d.,]}{}g;
	$_[1] = $price;
    }
};

sub _build_id {
    my $self = shift;
    return $self->sku . "::" . 1; 
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

