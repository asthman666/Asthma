package Asthma::File;
use Moose::Role;
use namespace::autoclean;
use XML::Twig;

has 'xml_twig' => ( is => 'rw', isa => 'XML::Twig', lazy_build => 1 );

sub _build_xml_twig {
    my $self = shift;
    my $twig = XML::Twig->new();       
    return $twig;
}

sub wf {
    my $self      = shift;
    my $items     = shift;
    return unless $items && ref($items) eq "ARRAY";
    
    my $file;

    my $pn = ref($self);
    if ( $pn =~ m{Spider::(.+)} ) {
	$file = "file/" . $1 . ".txt";
    }

    my $root = XML::Twig::Elt->new;
    $root->set_tag("add");
    $self->xml_twig->set_root($root);

    open my $fh, ">", $file;

    foreach my $item ( @$items ) {
	
	$self->xml_twig->print;
	$self->xml_twig->flush($fh);
	last;
    }

    close $fh;
}

1;
