package POE::Component::Github::Request::Repositories;

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
        	search
        	show
        	list
        	network
        	tags
        	branches
        	watch
        	unwatch
        	fork
        	create
        	delete
        	set_private
        	set_public
        	deploy_keys
        	add_deploy_key
        	remove_deploy_key
        	collaborators
        	add_collaborator
        	remove_collaborator
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

#Repositories
#  - public ->
#       - search - repos/search/:q
#       - show - repos/show/:user/:repo
#       - list - repos/show/:user [ also auth ]
#       - network - repos/show/:user/:repo/network
#       - tags - repos/show/:user/:repo/tags
#       - branches - repos/show/:user/:repo/branches
#  - authenticated ->
#       - watch - repos/watch/:user/:repo
#       - unwatch - repos/unwatch/:user/:repo
#       - fork - repos/fork/:user/:repo
#       - create - repos/create
#       - delete - repos/delete/:repo
#       - set_private - repos/set/private/:repo
#       - set_public - repos/set/public/:repo
#       - deploy_keys - repos/keys/:repo
#       - add_deploy_key - repos/key/:repo/add
#       - remove_deploy_key - repos/key/:repo/remove
#       - collaborators - repos/show/:user/:repo/collaborators
#       - add_collaborator - repos/collaborators/:repo/add/:user
#       - remove_collaborator - repos/collaborators/:repo/remove/:user

sub request {
  my $self = shift;
  AUTHENTICATED: {
    if ( $self->login and $self->token ) { # Okay authenticated required.
       if ( grep { $_ eq $self->cmd } qw(search show network tags branches) ) {
	  last AUTHENTICATED;
       }
       # Simple stuff no values required.
       my $data = [ login => $self->login, token => $self->token ];
       if ( $self->cmd =~ /^(watch|unwatch|fork|collaborators)$/ ) {
          my $url = 'https://' . join '/', $self->api_url, 'repos';
	  return POST( join('/',$url,$self->user,$self->repo,$self->cmd), $data ) if $self->cmd eq 'collaborators';
	  return POST( join('/',$url,$self->cmd,$self->user,$self->repo), $data );
       }
       if ( my ($cmd) = $self->cmd =~ /^set_(private|public)$/ ) {
	  return POST( 'https://' . join('/', $self->api_url, 'repos', 'set', $cmd, $self->repo), $data );
       }
    }
  }
  if ( $self->cmd eq 'search' ) {
     return GET( $self->scheme . join '/', $self->api_url, 'repos', 'search', $self->repo );
  }
  if ( $self->cmd =~ /^(show|list|network|tags|branches)$/ ) {
     my $url = $self->scheme . join '/', $self->api_url, 'repos', 'show', $self->user;
     return GET( $url ) if $self->cmd eq 'list';
     return GET( join '/', $url, $self->repo ) if $self->cmd eq 'show';
     return GET( join '/', $url, $self->repo, $self->cmd );
  }
}

no Moose;

1;
__END__
