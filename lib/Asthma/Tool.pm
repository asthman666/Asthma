package Asthma::Tool;
use Moose::Role;
use Image::OCR::Tesseract qw(get_ocr);
use LWP::Simple qw(getstore);
use namespace::autoclean;
use Asthma::Debug;

sub get_price {
    my $self = shift;
    my $price_url = shift;

    if ( $price_url =~ m{.+/(.+\.png)} ) {
        my $file = "/tmp/img/$1";
        my $code = getstore($price_url, $file);
        my $text = get_ocr($file);
        # 3’|99.00
	my $sp = '’\|';
	use Encode;
	Encode::_utf8_off($sp);
        $text =~ s{$sp}{1}g;
        return $text;
    }
    
    return 0;    
}

1;
