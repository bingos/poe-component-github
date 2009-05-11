use strict;
use warnings;
use Test::More;

my @modules = qw(
  POE::Component::Github
  POE::Component::Github::Request::Role
  POE::Component::Github::Request::Users
);

plan tests => scalar @modules;
use_ok($_) for @modules;
