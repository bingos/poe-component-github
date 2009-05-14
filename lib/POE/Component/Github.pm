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
  $kernel->refcount_increment( $args->{session}, __PACKAGE__ ) unless $args->{postback};
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
	values   => $args->{values},
  );
  $args->{req} = $req->request();
  warn $args->{req}->as_string;
  $args->{session} = $sender->ID;
  $kernel->refcount_increment( $args->{session}, __PACKAGE__ ) unless $args->{postback};
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
  $kernel->refcount_increment( $args->{session}, __PACKAGE__ ) unless $args->{postback};
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
  $kernel->refcount_increment( $args->{session}, __PACKAGE__ ) unless $args->{postback};
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
  $kernel->refcount_increment( $args->{session}, __PACKAGE__ ) unless $args->{postback};
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
  $kernel->refcount_increment( $args->{session}, __PACKAGE__ ) unless $args->{postback};
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

Where C<EVENT> is either C<user>, C<repositories>, C<commits>, C<object>, C<issues> or C<network>.

Where authentication is required it will be indicated. This may be either provided during C<spawn>
or provided as arguments to each command. You may obtain the token for your Github account from
https://github.com/account

Three options are common to all commands, C<event>, C<session> and C<postback>.

=over

=item C<event>

The name of the event in the requesting session to send the results. Mandatory unless C<postback> is specified.

=item C<session>

Specify that an alternative session receive the results C<event> instead, purely optional, the default is to send
to the requesting session.

=item C<postback>

Instead of specifying an C<event>, one may specify a L<POE::Session> C<postback> instead. See the docs for L<POE::Session>
for more details.

=back

=head2 User API

L<http://develop.github.com/p/users.html>

Searching users, getting user information and managing authenticated user account information.

Send the event C<user> with one of the following commands:

=over

=item C<search>

Search for users. Provide the parameter C<user> to search for.
  
  $poe_kernel->post( $github->get_session_id, 
	'user', 'search', { event => '_search', user => 'moocow' } );

=item C<show>

Show extended information about a user. Provide the parameter C<user> to query.

  $poe_kernel->post( $github->get_session_id, 
	'user', 'show', { event => '_show', user => 'moocow' } );

If authentication credentials are provided a C<show> on your own C<user> will have extra extended information
regarding disk usage etc.

=item C<following>

Obtain a list of the people a C<user> is following. Provide the parameter C<user> to query.

  $poe_kernel->post( $github->get_session_id, 
	'user', 'following', { event => '_following', user => 'moocow' } );

=item C<followers>

Obtain a list of the people who are following a C<user>. Provide the parameter C<user> to query.

  $poe_kernel->post( $github->get_session_id, 
	'user', 'followers', { event => '_followers', user => 'moocow' } );

=back

These following commands require authentication:

Where data values are required these should be passed via the C<values> parameter which should be a hashref of
key/value pairs.

=over

=item C<update>

Update your user information. Provide name, email, blog, company, location as keys to C<values>.

  $poe_kernel->post( $github->get_session_id, 'user', 'update',
	  { 
	    event  => '_update', 
	    login  => 'moocow',
	    token  => '54b5197d7f92f52abc5c7149b313cf51', # faked
	    values => 
	    {
		name     => 'Mr. Cow',
		location => 'The Farm',
		email    => 'moocow@moo.cow',
	    },
          } 
  );

=item C<follow>

Follow a particular C<user>. Provide the parameter C<user> to follow.

  $poe_kernel->post( $github->get_session_id, 'user', 'follow',
	  { 
	    event => '_follow', 
	    login  => 'moocow',
	    token  => '54b5197d7f92f52abc5c7149b313cf51', # faked
	    user => 'pigdog' 
	  } 
  );

=item C<unfollow>

Stop following a particular C<user>. Provide the parameter C<user> to unfollow.

  $poe_kernel->post( $github->get_session_id, 'user', 'unfollow',
	  { 
	    event => '_unfollow', 
	    login  => 'moocow',
	    token  => '54b5197d7f92f52abc5c7149b313cf51', # faked
	    user => 'pigdog' 
	  } 
  );

=item C<pub_keys>

List your public keys.

  $poe_kernel->post( $github->get_session_id, 'user', 'pub_keys',
	  { 
	    event => '_pubkeys', 
	    login  => 'moocow',
	    token  => '54b5197d7f92f52abc5c7149b313cf51', # faked
	  } 
  );

=item C<add_key>

Add a public key. Requires a C<name> and the C<key> passed as C<values>.

  $poe_kernel->post( $github->get_session_id, 'user', 'add_key',
	  { 
	    event => '_addkey', 
	    login  => 'moocow',
	    token  => '54b5197d7f92f52abc5c7149b313cf51', # faked
	    values => 
	    {
		name     => 'My Public Key',
		'key'	 => $some_public_key,
	    },
	  } 
  );

=item C<remove_key>

Removes a public key. Requires a key C<id> passed as C<values>.

  $poe_kernel->post( $github->get_session_id, 'user', 'remove_key',
	  { 
	    event => '_removekey', 
	    login  => 'moocow',
	    token  => '54b5197d7f92f52abc5c7149b313cf51', # faked
	    values => 
	    {
		id	 => $key_id,
	    },
	  } 
  );

=item C<emails>

List your emails.

  $poe_kernel->post( $github->get_session_id, 'user', 'emails',
	  { 
	    event => '_emails', 
	    login  => 'moocow',
	    token  => '54b5197d7f92f52abc5c7149b313cf51', # faked
	  } 
  );

=item C<add_email>

Adds an email. Requires an C<email> passed as C<values>.

  $poe_kernel->post( $github->get_session_id, 'user', 'add_email',
	  { 
	    event => '_addemail', 
	    login  => 'moocow',
	    token  => '54b5197d7f92f52abc5c7149b313cf51', # faked
	    values => 
	    {
		email	 => 'moocow@thefarm.cow',
	    },
	  } 
  );

=item C<remove_email>

Removes an existing email. Requires an C<email> passed as C<values>.

  $poe_kernel->post( $github->get_session_id, 'user', 'remove_email',
	  { 
	    event => '_removeemail', 
	    login  => 'moocow',
	    token  => '54b5197d7f92f52abc5c7149b313cf51', # faked
	    values => 
	    {
		email	 => 'moocow@thefarm.cow',
	    },
	  } 
  );

=back

=head2 Repository API

L<http://develop.github.com/p/repo.html>

Searching repositories, getting repository information and managing authenticated repository information.

Send the event C<repositories> with one of the following commands:

=over

=item C<search>

Search for a repository. Provide the parameter C<user> to search for.

   $poe_kernel->post( $github->get_session_id,
         'repositories', 'search', { event => '_search', repo => 'the-barn' } );

=item C<show>

To look at more in-depth information for a repository. Provide C<user> and C<repo> for the repository.

   $poe_kernel->post( $github->get_session_id,
         'repositories', 'show', { event => '_show', user => 'moocow', repo => 'the-barn' } );


=item C<list>

List out all the repositories for a user. Provide the C<user> to look at.

   $poe_kernel->post( $github->get_session_id,
         'repositories', 'list', { event => '_list', user => 'moocow' } );

=item C<network>

Look at the full network for a repository. Provide the C<user> and C<repo>.

   $poe_kernel->post( $github->get_session_id,
         'repositories', 'network', { event => '_network', user => 'moocow', repo => 'the-barn' } );

=item C<tags>

List the tags for a repository. Provide the C<user> and C<repo>.

   $poe_kernel->post( $github->get_session_id,
         'repositories', 'tags', { event => '_tags', user => 'moocow', repo => 'the-barn' } );

=item C<branches>

List the branches for a repository. Provide the C<user> and C<repo>.

   $poe_kernel->post( $github->get_session_id,
         'repositories', 'branches', { event => '_branches', user => 'moocow', repo => 'the-barn' } );

=item C<collaborators>

List the collaborators for a repository. Provide the C<user> and C<repo>.

  $poe_kernel->post( $github->get_session_id, 'repositories', 'collaborators',
	  { 
	    event => '_collaborators', 
	    user  => 'moocow',
	    repo  => 'the-barn',
	  } 
  );

=back

These following commands require authentication:

Where data values are required these should be passed via the C<values> parameter which should be a hashref of
key/value pairs.

=over

=item C<watch>

Start watching a repository. Provide the C<user> and C<repo> to watch.

  $poe_kernel->post( $github->get_session_id, 'repositories', 'watch',
	  { 
	    event => '_watch', 
	    login  => 'moocow',
	    token  => '54b5197d7f92f52abc5c7149b313cf51', # faked
	    user   => 'pigdog',
	    repo   => 'the-field',
	  } 
  );

=item C<unwatch>

Stop watching a repository. Provide the C<user> and C<repo> to unwatch.

  $poe_kernel->post( $github->get_session_id, 'repositories', 'unwatch',
	  { 
	    event => '_unwatch', 
	    login  => 'moocow',
	    token  => '54b5197d7f92f52abc5c7149b313cf51', # faked
	    user   => 'pigdog',
	    repo   => 'the-field',
	  } 
  );

=item C<fork>

Fork a repository. Provide the C<user> and C<repo> to fork.

  $poe_kernel->post( $github->get_session_id, 'repositories', 'fork',
	  { 
	    event => '_fork', 
	    login  => 'moocow',
	    token  => '54b5197d7f92f52abc5c7149b313cf51', # faked
	    user   => 'pigdog',
	    repo   => 'the-field',
	  } 
  );

=item C<create>

Create a new repository. 

  $poe_kernel->post( $github->get_session_id, 'repositories', 'create',
	  { 
	    event => '_create', 
	    login  => 'moocow',
	    token  => '54b5197d7f92f52abc5c7149b313cf51', # faked
	    values => 
	    {
		name 		=> 'the-meadow',
		description 	=> 'The big meadow with the stream',
		homepage 	=> 'http://moo.cow/meadow/'
		public 		=> 1,	# Or 0 for private
	    },
	  } 
  );

=item C<delete>

Delete one of your repositories. Provide C<repo>. The first return from this will contain a C<delete_token>.
Submit the delete request again, passing the C<delete_token> in C<values>.

  $poe_kernel->post( $github->get_session_id, 'repositories', 'delete',
	  { 
	    event => '_delete_token', 
	    login  => 'moocow',
	    token  => '54b5197d7f92f52abc5c7149b313cf51', # faked
	    repo   => 'the-meadow',
	  } 
  );

  $poe_kernel->post( $github->get_session_id, 'repositories', 'delete',
	  { 
	    event => '_delete', 
	    login  => 'moocow',
	    token  => '54b5197d7f92f52abc5c7149b313cf51', # faked
	    repo   => 'the-meadow',
	    values => 
	    {
		delete_token 	=> $delete_token,
	    },
	  } 
  );

=item C<set_private>

Make a public repository private. Provide the C<repo> to make private.

  $poe_kernel->post( $github->get_session_id, 'repositories', 'set_private',
	  { 
	    event => '_set_private', 
	    login  => 'moocow',
	    token  => '54b5197d7f92f52abc5c7149b313cf51', # faked
	    repo   => 'the-meadow',
	  } 
  );

=item C<set_public>

Make a private repository public. Provide the C<repo> to make public.

  $poe_kernel->post( $github->get_session_id, 'repositories', 'set_public',
	  { 
	    event => '_set_public', 
	    login  => 'moocow',
	    token  => '54b5197d7f92f52abc5c7149b313cf51', # faked
	    repo   => 'the-meadow',
	  } 
  );

=item C<deploy_keys>

List the deploy keys for a repository. Provide the C<repo>.

  $poe_kernel->post( $github->get_session_id, 'repositories', 'deploy_keys',
	  { 
	    event => '_deploy_keys', 
	    login  => 'moocow',
	    token  => '54b5197d7f92f52abc5c7149b313cf51', # faked
	    repo   => 'the-meadow',
	  } 
  );

=item C<add_deploy_key>

Add a deploy key. Provide the C<repo> and the C<title> and C<key> as C<values>.

  $poe_kernel->post( $github->get_session_id, 'repositories', 'add_deploy_key',
	  { 
	    event => '_add_deploy_key', 
	    login  => 'moocow',
	    token  => '54b5197d7f92f52abc5c7149b313cf51', # faked
	    repo   => 'the-meadow',
	    values => 
	    {
		title => $title,
		key   => $key,
	    },
	  } 
  );

=item C<remove_deploy_key>

Remove a deploy key. Provide the C<repo> and the key id C<id> as C<values>.

  $poe_kernel->post( $github->get_session_id, 'repositories', 'remove_deploy_key',
	  { 
	    event => '_remove_deploy_key', 
	    login  => 'moocow',
	    token  => '54b5197d7f92f52abc5c7149b313cf51', # faked
	    repo   => 'the-meadow',
	    values => 
	    {
		id => $key_id,
	    },
	  } 
  );

=item C<add_collaborator>

Add a collaborator to one of your repositories. Provide C<repo> and the C<user> to add.

  $poe_kernel->post( $github->get_session_id, 'repositories', 'add_collaborator',
	  { 
	    event => '_add_collaborator', 
	    login  => 'moocow',
	    token  => '54b5197d7f92f52abc5c7149b313cf51', # faked
	    repo   => 'the-meadow',
	    user   => 'pigdog',
	  } 
  );

=item C<remove_collaborator>

Remove a collaborator from one of your repositories. Provide C<repo> and the C<user> to remove.

  $poe_kernel->post( $github->get_session_id, 'repositories', 'remove_collaborator',
	  { 
	    event => '_remove_collaborator', 
	    login  => 'moocow',
	    token  => '54b5197d7f92f52abc5c7149b313cf51', # faked
	    repo   => 'the-meadow',
	    user   => 'pigdog',
	  } 
  );

=back

=head2 Commit API

=head2 Object API

=head2 Issues API

=head2 Network API

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
