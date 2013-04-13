#!/usr/bin/perl
use strict;
use warnings;
use FindBin qw/$Bin/;
use DBIx::Class::Schema::Loader qw/ make_schema_at /;

my $user = shift;
my $password = shift;
my $dsn = 'dbi:mysql:asthma';

make_schema_at(
    'Asthma::Schema',
    { debug => 1,
      dump_directory => "$Bin/../lib",
      use_moose => 1,
    },
    [ $dsn, $user, $password ]
);
