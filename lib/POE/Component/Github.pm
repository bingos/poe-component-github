package POE::Component::Github;

use strict;
use warnings;
use POE::Component::Client::HTTP;
use HTTP::Request::Common;
use Algorithm::FloodControl;
use JSON::Any;
use Class::MOP;
use Module::Pluggable search_path => ['POE::Component::Github::Request'], except => 'POE::Component::Github::Request::Role';
use vars qw($VERSION);

$VERSION = '0.02';

# Stolen from POE::Wheel. This is static data, shared by all
my $current_id = 0;
my %active_identifiers;

sub _allocate_identifier {
  while (1) {
    last unless exists $active_identifiers{ ++$current_id };
  }
  return $active_identifiers{$current_id} = $current_id;
}

sub _free_identifier {
  my $id = shift;
  delete $active_identifiers{$id};
}

use MooseX::POE;

has login => (
    is      => 'ro',
    isa     => 'Str',
    default => '',
);

has token => (
    is      => 'ro',
    isa     => 'Str',
    default => '',
);

has scheme => (
    is      => 'ro',
    isa     => 'Str',
    default => 'http://',
);

has auth_scheme => (
    is      => 'ro',
    isa     => 'Str',
    default => 'https://',
);

has url_path => (
    is      => 'ro',
    default => 'github.com/api/v2/json',
);

has _http_alias => (
    is      => 'rw',
    isa     => 'Str',
    default => '',
);

has 'json' => (
    is => 'ro',
    isa => 'JSON::Any',
    lazy => 1,
    default => sub {
        return JSON::Any->new;
    }
);

has _requests => (
    is => 'ro',
    default => sub { { } },
);

has _shutdown => (
    is => 'rw',
    default => 0,
);

sub spawn {
  shift->new(@_);
}

sub START {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
  $self->_http_alias( join '-', __PACKAGE__, $self->get_session_id );
  $kernel->refcount_increment( $self->get_session_id, __PACKAGE__ );
  POE::Component::Client::HTTP->spawn(
	Alias           => $self->_http_alias,
	FollowRedirects => 2,
  );
  Class::MOP::load_class($_) for $self->plugins();
  return;
}

event shutdown => sub {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
  $kernel->refcount_decrement( $self->get_session_id, __PACKAGE__ );
  $kernel->post( $self->_http_alias, 'shutdown' );
  $self->_shutdown(1);
  return;
};

sub _validate_args {
  my $self = shift;
  my $sender = shift || return;
  my $state = shift || return;
  my $args;
  if ( ref $_[0] eq 'HASH' ) {
     $args = $_[0];
  }
  else {
     $args = { @_ };
  }
  # check stuff
  use Data::Dump::Streamer qw(Dumper);
  warn Dumper( $args );
  $args->{lc $_} = delete $args->{$_} for grep { $_ !~ /^_/ } keys %{ $args };
  delete $args->{postback} unless defined $args->{postback} and ref $args->{postback} eq 'POE::Session::AnonEvent';
  unless ( $args->{postback} ) {
     unless ( $args->{event} ) {
       warn "No 'event' specified for $state\n";
       return;
     }
     if ( $args->{session} and my $ref = $poe_kernel->alias_resolve( $args->{session} ) ) {
       $args->{session} = $ref->ID();
     }
     else {
       $args->{session} = $sender->ID();
     }
  }
  return $args;
}

event user => sub {
  my ($kernel,$self,$state,$sender,$cmd) = @_[KERNEL,OBJECT,STATE,SENDER,ARG0];
  return if $self->_shutdown;
  my $args = $self->_validate_args( $sender, $state, @_[ARG1..$#_] );
  return unless $args;
  # build url
  $args->{_state} = $state;
  $args->{cmd} = lc $cmd;
  my $req = POE::Component::Github::Request::Users->new(
	api_url  => $self->url_path,
	cmd      => $args->{cmd},
	login    => $args->{login} || $self->login,
	token    => $args->{token} || $self->token,
	user     => $args->{user},
	values   => $args->{values},
  );
  $args->{req} = $req->request();
  $kernel->refcount_increment( $args->{session}, __PACKAGE__ );
  $kernel->yield( '_dispatch_cmd', $args );
  return;
};

event repositories => sub {
  my ($kernel,$self,$state,$sender,$cmd) = @_[KERNEL,OBJECT,STATE,SENDER,ARG0];
  return if $self->_shutdown;
  # check stuff
  my $args = $self->_validate_args( $sender, $state, @_[ARG1..$#_] );
  return unless $args;
  # build url
  $args->{_state} = $state;
  $args->{cmd} = lc $cmd;
  my $req = POE::Component::Github::Request::Repositories->new(
	api_url  => $self->url_path,
	cmd      => $args->{cmd},
	login    => $args->{login} || $self->login,
	token    => $args->{token} || $self->token,
	user     => $args->{user},
	repo	 => $args->{repo},
  );
  $args->{req} = $req->request();
  $args->{session} = $sender->ID;
  $kernel->refcount_increment( $args->{session}, __PACKAGE__ );
  $kernel->yield( '_dispatch_cmd', $args );
  return;
};

event commits => sub {
  my ($kernel,$self,$state,$sender,$cmd) = @_[KERNEL,OBJECT,STATE,SENDER,ARG0];
  return if $self->_shutdown;
  # check stuff
  my $args = $self->_validate_args( $sender, $state, @_[ARG1..$#_] );
  return unless $args;
  # build url
  $args->{_state} = $state;
  $args->{cmd} = lc $cmd;
  my $req = POE::Component::Github::Request::Commits->new(
	api_url  => $self->url_path,
	cmd      => $args->{cmd},
	user     => $args->{user},
	repo	 => $args->{repo},
	branch   => $args->{branch} || 'master',
	file     => $args->{file},
	commit   => $args->{commit},
  );
  $args->{req} = $req->request();
  $args->{session} = $sender->ID;
  $kernel->refcount_increment( $args->{session}, __PACKAGE__ );
  $kernel->yield( '_dispatch_cmd', $args );
  return;
};

event object => sub {
  my ($kernel,$self,$state,$sender,$cmd) = @_[KERNEL,OBJECT,STATE,SENDER,ARG0];
  return if $self->_shutdown;
  # check stuff
  my $args = $self->_validate_args( $sender, $state, @_[ARG1..$#_] );
  return unless $args;
  # build url
  $args->{_state} = $state;
  $args->{cmd} = lc $cmd;
  my $req = POE::Component::Github::Request::Object->new(
	api_url  => $self->url_path,
	cmd      => $args->{cmd},
	user     => $args->{user},
	repo	 => $args->{repo},
	tree_sha => $args->{tree_sha},
	path     => $args->{path},
	sha      => $args->{sha},
  );
  $args->{req} = $req->request();
  $args->{session} = $sender->ID;
  $kernel->refcount_increment( $args->{session}, __PACKAGE__ );
  $kernel->yield( '_dispatch_cmd', $args );
  return;
};

event network => sub {
  my ($kernel,$self,$state,$sender,$cmd) = @_[KERNEL,OBJECT,STATE,SENDER,ARG0];
  return if $self->_shutdown;
  # check stuff
  my $args = $self->_validate_args( $sender, $state, @_[ARG1..$#_] );
  return unless $args;
  # build url
  $args->{_state} = $state;
  $args->{cmd} = lc $cmd;
  my $req = POE::Component::Github::Request::Network->new(
	api_url  => $self->url_path,
	cmd      => $args->{cmd},
	user     => $args->{user},
	repo	 => $args->{repo},
	nethash	 => $args->{nethash},
	start    => $args->{start},
	end      => $args->{end},
  );
  $args->{req} = $req->request();
  $args->{session} = $sender->ID;
  $kernel->refcount_increment( $args->{session}, __PACKAGE__ );
  $kernel->yield( '_dispatch_cmd', $args );
  return;
};

event issues => sub {
  my ($kernel,$self,$state,$sender,$cmd) = @_[KERNEL,OBJECT,STATE,SENDER,ARG0];
  return if $self->_shutdown;
  # check stuff
  my $args = $self->_validate_args( $sender, $state, @_[ARG1..$#_] );
  return unless $args;
  # build url
  $args->{_state} = $state;
  $args->{cmd} = lc $cmd;
  my $req = POE::Component::Github::Request::Issues->new(
	api_url  => $self->url_path,
	cmd      => $args->{cmd},
	user     => $args->{user},
	repo	 => $args->{repo},
	search   => $args->{search},
	id       => $args->{id},
	label    => $args->{label},
	state    => $args->{state},
	values   => $args->{values},
  );
  $args->{req} = $req->request();
  $args->{session} = $sender->ID;
  $kernel->refcount_increment( $args->{session}, __PACKAGE__ );
  $kernel->yield( '_dispatch_cmd', $args );
  return;
};

event _dispatch_cmd => sub {
  my ($kernel,$self,$args) = @_[KERNEL,OBJECT,ARG0];
  my $wait = flood_check( 60, 60, __PACKAGE__ );
  if ( $wait ) {
     $kernel->delay_set( '_dispatch_cmd', $wait, $args );
     return;
  }
  my $id = _allocate_identifier();
  my $req = delete $args->{req};
  $kernel->post( 
    $self->_http_alias, 
    'request',
    '_response',
    $req, 
    "$id",
  );
  $self->_requests->{ $id } = $args;
  return;
};

event _response => sub {
  my ($kernel,$self,$request_packet,$response_packet) = @_[KERNEL,OBJECT,ARG0,ARG1];
  my $id = $request_packet->[1];
  my $args = delete $self->_requests->{ $id };
  _free_identifier( $id );
  my $resp = $response_packet->[0];
  if ( !$resp->is_success ) {
     $args->{error} = $resp->as_string;
     $args->{error} = '404 Not found' if $resp->code == 404;
  }
  else {
     my $json = $resp->content();
     if ( $args->{_state} eq 'object' and $args->{cmd} eq 'raw' ) {
        $args->{data} = $json;
     }
     else {
        $args->{data} = $self->json->jsonToObj($json);
     }
  }
  my $postback = delete $args->{postback};
  if ( $postback ) {
    $postback->( $args );
    return;
  }
  my $session  = delete $args->{session};
  my $event    = delete $args->{event};
  $kernel->post( $session, $event, $args );
  $kernel->refcount_decrement( $session, __PACKAGE__ );
  return;
};

no MooseX::POE;

#__PACKAGE__->meta->make_immutable;

'Moooooooooooose!';
__END__

=head1 NAME

POE::Component::Github - A POE component for the Github API

=head1 SYNOPSIS

=head1 DESCRIPTION

POE::Component::Github is a L<POE> component that provides asynchronous access to the Github API L<http://develop.github.com/>
to other POE sessions or components. It was inspired by L<Net::Github>.

The component handles communicating with the Github API and will parse the JSON data returned into perl data structures for you.

The component also implements flood control to ensure that no more than 60 requests are made per minute ( which is the current
limit ).

=head1 CONSTRUCTOR

=over

=item C<spawn>

Spawns a new POE::Component::Github session and returns an object. Takes a number of optional parameters:

  'login', provide a default login name to use for authenticated requests;
  'token', provide a default Github API token to use for authenticated requests;

=back

=head1 METHODS

The following methods are available from the object returned by C<spawn>.

=over

=item C<get_session_id>

Returns the POE session ID of the component's session.

=item C<yield>

Send an event to the component's session.

=back

=head1 INPUT EVENTS

These are events that the component will accept. The format of all events is:

  $poe_kernel->post( POCO_GITHUB, EVENT, COMMAND, HASHREF_OF_OPTIONS );

or

  $github_object->yield( EVENT, COMMAND, HASHREF_OF_OPTIONS );

=over

=item C<

=back

=head1 OUTPUT EVENTS

=head1 AUTHOR

Chris C<BinGOs> Williams <chris@bingosnet.co.uk>

=head1 KUDOS

Fayland for L<Net::Github> and doing the dog-work of translating the Github API.

Chris C<perigrin> Prather for L<MooseX::POE>

Github L<http://github.com/>

=head1 LICENSE

Copyright E<copy> Chris Williams

This module may be used, modified, and distributed under the same terms as Perl itself. Please see the license that came with your Perl distribution for details.

=head1 SEE ALSO

L<http://develop.github.com/>

L<Net::Github>

L<MooseX::POE>

=cut
