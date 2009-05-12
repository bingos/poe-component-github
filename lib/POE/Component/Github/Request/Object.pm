package POE::Component::Github::Request::Object;

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
		tree
		blob
		raw
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

has tree_sha => (
  is       => 'ro',
  default  => '',
);

has path => (
  is       => 'ro',
  default  => '',
);

has sha => (
  is       => 'ro',
  default  => '',
);

# Commits

sub request {
  my $self = shift;
  # No authenticated requests
  my $url = $self->scheme . $self->api_url;
  if ( $self->cmd =~ /^(tree|blob)$/ ) {
     $url = join '/', $url, $self->cmd, 'show', $self->user, $self->repo, $self->tree_sha;
     return GET( $self->cmd eq 'blob' ? join('/', $url, $self->path) : $url );
  }
  if ( $self->cmd eq 'raw' ) {
     return GET( join('/', $url, 'blob', 'show', $self->user, $self->repo, ( $self->sha || $self->tree_sha ) ) );
  }
}

no Moose;

__PACKAGE__->meta->make_immutable;

1;
__END__
