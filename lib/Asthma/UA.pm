package Asthma::UA;

use Moose::Role;
use namespace::autoclean;
use Class::Load 'load_class';

has 'ua_class' => (is => 'rw', isa => 'Str', default => 'LWP::UserAgent');

has 'ua_args'  => (is => 'rw', isa => 'HashRef', default => sub { {
    agent   => 'Mozilla/5.0 (Windows NT 6.1; rv:17.0) Gecko/20100101 Firefox/17.0',
} });

has 'headers' => (is => 'rw', isa => 'HashRef', 
		  default => sub { 
		      {
			  "user-agent" => "Mozilla/5.0 (Windows NT 6.1; rv:17.0) Gecko/20100101 Firefox/17.0",
			  "Accept-Encoding" => "gzip, deflate",
			  'Accept-Language' => "zh-cn,zh;q=0.8,en-us;q=0.5,en;q=0.3",
			  'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
		      } 
		  });

has 'ua' => (
    is => 'rw',
    lazy_build => 1
);

sub _build_ua {
    my $self = shift;
    my $class = $self->ua_class;
    load_class($class) or die;
    my $ua = $class->new( %{$self->ua_args} );
    $ua->default_header('Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
    $ua->default_header('Accept-Encoding' => 'gzip, deflate');
    $ua->default_header('Accept-Language' => "zh-cn,zh;q=0.8,en-us;q=0.5,en;q=0.3");
    return $ua;
}

1;

