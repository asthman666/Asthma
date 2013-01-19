package Asthma::Item;
use Moose;

use Data::Dumper;

has ['title', 'image_url', 'ean', 'sku', 'url'] => (is => 'rw', isa => 'Str');
has 'price' => (is => 'rw');
has 'id' => (is => 'rw', isa => 'Str');
has 'dt_created' => (is => 'rw', isa => 'Str', lazy_build => 1);
has 'dt_expire' => (is => 'rw', isa => 'Str', lazy_build => 1);

before 'title' => sub {
    if ( my $title = $_[1] ) {
	$title =~ s{\s+$}{};
	$title =~ s{^\s+}{};
	$title =~ s{\s+}{ }g;
	$_[1] = $title;
    }
};

before 'ean' => sub {
    if ( my $ean = $_[1] ) {
	$ean =~ s{[^\d]}{}g;
	$_[1] = $ean;
    }
};

before 'price' => sub {
    if ( my $price = $_[1] ) {
	$price =~ s{[^\d.]}{}g;
        $price = sprintf("%.2f", $price);
	$_[1] = $price;
    }
};

sub _build_dt_created {
    my $self = shift;
    my @arr = localtime;
    return ($arr[5]+1900) . "-" . ($arr[4]+1) . "-" . $arr[3] . "T" . $arr[2] . ":" . $arr[1] . ":" . $arr[0] . "Z";
}

sub _build_dt_expire {
    my $self = shift;
    my @arr = localtime(time+3600*24*10);
    return ($arr[5]+1900) . "-" . ($arr[4]+1) . "-" . $arr[3] . "T" . $arr[2] . ":" . $arr[1] . ":" . $arr[0] . "Z";
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

