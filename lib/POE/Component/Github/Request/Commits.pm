package POE::Component::Github::Request::Commits;

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
		branch
		file
		commit
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

has branch => (
  is       => 'ro',
  default  => 'master',
);

has file => (
  is       => 'ro',
  default  => '',
);

has commit => (
  is       => 'ro',
  default  => '',
);

# Commits

sub request {
  my $self = shift;
  # No authenticated requests
  my $url = $self->scheme . join '/', $self->api_url, 'commits';
  if ( $self->cmd =~ /^(branch|file)$/ ) {
     return GET( join('/', $url, 'list', $self->user, $self->repo, $self->branch, ( $self->cmd eq 'file' ? $self->file : () )) );
  }
  if ( $self->cmd eq 'commit' ) {
     return GET( join('/', $url, 'show', $self->user, $self->repo, $self->commit) );
  }
}

no Moose;

1;
__END__
