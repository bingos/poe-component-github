use strict;
use warnings;
use Test::More;

my @modules = qw(
  POE::Component::Github
  POE::Component::Github::URL::Role
  POE::Component::Github::URL::Users
);

plan tests => scalar @modules;
use_ok($_) for @modules;
