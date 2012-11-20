use FindBin qw($Bin);
use lib "$Bin/../lib";
use Asthma::LinkExtractor;
use LWP::UserAgent;
use Data::Dumper;

my $l = Asthma::LinkExtractor->new;

$l->allow(['tag']);
$l->deny(['tags']);

my $ua = LWP::UserAgent->new();

my $resp = $ua->get("http://www.yishuiyixu.com");
my @links = $l->extract_links($resp);

print Dumper \@links;

