package Asthma::Amazon;
use Moose;
with 'Asthma::UA';

use Asthma::Amazon::RequestSignatureHelper;

has 'access_key' => (is => 'ro', isa => 'Str', default => 'access_key');
has 'secret_key' => (is => 'ro', isa => 'Str', default => 'secret_key');
has 'associate_tag' => (is => 'ro', isa => 'Str', default => 'associate_tag');
has 'service' => (is => 'ro', isa => 'Str', default => 'AWSECommerceService');
has 'version' => (is => 'ro', isa => 'Str', default => '2011-08-01');
has 'myendpoint' => (is => 'ro', isa => 'Str', default => 'webservices.amazon.cn');
has 'helper' => (is => 'ro', lazy_build => 1);

sub _build_helper {
    my $self = shift;
    return Asthma::Amazon::RequestSignatureHelper->new(
	+Asthma::Amazon::RequestSignatureHelper::kAWSAccessKeyId => $self->access_key,
	+Asthma::Amazon::RequestSignatureHelper::kAWSSecretKey   => $self->secret_key,
	+Asthma::Amazon::RequestSignatureHelper::kEndPoint       => $self->myendpoint,
	);    
}

sub url {
    my $self   = shift;
    my $request = shift;

    $request->{Service}      = $self->service;
    $request->{AssociateTag} = $self->associate_tag;
    $request->{Version}      = $self->version;

    my $signed_request = $self->helper->sign($request);
    my $query_string = $self->helper->canonicalize($signed_request);
    return "http://" . $self->myendpoint . "/onca/xml?" . $query_string;
    
}

sub content {
    my $self   = shift;
    my $request = shift;

    my $url = $self->url($request);
    my $res = $self->ua->get($url);
    my $content = $res->decoded_content;

    return $content;
}


1;





