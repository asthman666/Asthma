package Asthma::LinkExtractor;
use Moose;
use HTML::LinkExtor;

has 'unique' => (is => 'rw', isa => 'Int', default => 1);

has 'allow' => (is => 'rw', isa => 'ArrayRef[Str]', default => sub { [] });

has 'deny' => (is => 'rw', isa => 'ArrayRef[Str]', default => sub { [] });

has 'allow_domain' => (is => 'rw', isa => 'ArrayRef[Str]', default => sub { [] });

has 'deny_domain' => (is => 'rw', isa => 'ArrayRef[Str]', default => sub { [] });

has 'xpath' => (is => 'rw', isa => 'Str');

has 'html_linkextor' => (is => 'rw', lazy_build => 1);

sub _build_html_linkextor {
    my $self = shift;
    my $html_linkextor = HTML::LinkExtor->new;
    return $html_linkextor;
}

sub extract_links {
    my $self = shift;
    my $resp = shift;

    my $base_uri = $resp->base;

    my $content = $resp->decoded_content;
    $self->html_linkextor->parse($content);
    my @links = $self->html_linkextor->links;

    my @urls;

    foreach my $link ( @links ) {
	my $uri = URI->new_abs( $link->[2], $base_uri );

	my $url = $uri->as_string;

	next unless $self->check_allow($url);
	next if $self->check_deny($url);

	push @urls, $url;
    }

    if ( $self->unique ) {
	my %seen;
	$seen{$_}++ for @urls;
	return keys %seen;
    }
    
    return @urls;
}

sub check_allow {
    my $self = shift;
    my $url = shift;
    
    if ( @{$self->allow} ) {
	foreach my $regex ( @{$self->allow} ) {
	    return 1 if $url =~ /$regex/;
	}
    } else {
	return 1;
    }

    return 0;
}

sub check_deny {
    my $self = shift;
    my $url = shift;

    if ( @{$self->deny} ) {
	foreach my $regex ( @{$self->deny} ) {
	    return 1 if $url =~ /$regex/;
	}
    }
    
    return 0;
}

no Moose;
__PACKAGE__->meta->make_immutable;


1;
