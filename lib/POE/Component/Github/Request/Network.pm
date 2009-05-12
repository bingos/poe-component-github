package POE::Component::Github::Request::Network;

use strict;
use warnings;
use HTTP::Request::Common;
use vars qw($VERSION);

$VERSION = '0.02';

use Moose;
use Moose::Util::TypeConstraints;

use URI::Escape;

with 'POE::Component::Github::Request::Role';

has cmd => (
  is       => 'ro',
  isa      => enum([qw(
		network_meta
		network_data_chunk
              )]),
  required => 1,
);

has user => (
  is       => 'ro',
  default  => '',
);

has repo => (
  is       => 'ro',
  default  => '',
);

has nethash => (
  is       => 'ro',
  default  => '',
);

has start => (
  is       => 'ro',
  default  => '',
);

has end => (
  is       => 'ro',
  default  => '',
);

# Commits

sub request {
  my $self = shift;
  # No authenticated requests
  my $base_url = ( split /\//, $self->api_url )[0] ;
  my $url = $self->scheme . join '/', $base_url, $self->user, $self->repo, $self->cmd;
  if ( $self->cmd eq 'network_data_chunk' ) {
     $url .= '?' . 'nethash=' . $self->nethash;
     $url .= '&start=' . $self->start if $self->start;
     $url .= '&end='   . $self->end   if $self->end;
  }
  return GET( $url );
}

no Moose;

__PACKAGE__->meta->make_immutable;

1;
__END__
