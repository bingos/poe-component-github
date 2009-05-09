use strict;
use warnings;
use Test::More tests => 1;
use POE qw(Component::Github);

my $github = POE::Component::Github->new();
isa_ok( $github, 'POE::Component::Github');

$poe_kernel->run();
exit 0;
