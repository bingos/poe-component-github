use strict;
use warnings;
use Test::More tests => 2;
use POE qw(Component::Github);

my $github = POE::Component::Github->spawn();
isa_ok( $github, 'POE::Component::Github');

POE::Session->create(
  package_states => [
	'main' => [qw(_start _github)],
  ],
);

$poe_kernel->run();
pass("Okay the kernel returned");
exit 0;

sub _start {
  $poe_kernel->post( $github->get_session_id, 'user', 'following', { event => '_github', user => 'bingos' }, );
  return;
}

sub _github {
  use Data::Dumper;
  warn Dumper($_[ARG0]);
  $poe_kernel->post( $github->get_session_id, 'shutdown' );
  return;
}
