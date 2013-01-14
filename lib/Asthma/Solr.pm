package Asthma::Solr;
use Moose;
use WWW::Curl::Easy;

has 'curl' => (is => 'rw', isa => 'WWW::Curl::Easy', lazy_build => 1);
has 'host' => (is => 'rw', isa => 'Str', default => 'localhost');
has 'port' => (is => 'rw', isa => 'Int', default => '8983');
has 'update_url' => (is => 'rw', isa => 'Str', lazy_build => 1);

sub _build_update_url {
    my $self = shift;
    return "http://" . $self->host . ":" . $self->port . "/solr/update";
}

sub _build_curl {
    my $self = shift;
    my $curl = WWW::Curl::Easy->new();
    $curl->setopt(CURLOPT_FAILONERROR, 1);
    $curl->setopt(CURLOPT_FOLLOWLOCATION, 1);
    $curl->setopt(CURLOPT_HTTPHEADER, ['Content-type: text/xml; charset=utf-8']);
    $curl->setopt(CURLOPT_CUSTOMREQUEST, "POST");
    return $curl;
}

sub update {
    my $self  = shift;
    my $str   = shift;
    $self->curl->setopt(CURLOPT_URL, $self->update_url);
    $self->curl->setopt(CURLOPT_POSTFIELDS, $str);
    my $ret = $self->curl->perform;
    if ( $ret == 0 ) {
	$self->curl->setopt(CURLOPT_POSTFIELDS, '<commit/>');
	$self->curl->perform();
    }
    return $ret;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

