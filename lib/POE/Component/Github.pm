package POE::Component::Github;

use strict;
use warnings;
use POE::Component::Client::HTTP;
use HTTP::Request::Common;
use Algorithm::FloodControl;
use JSON::Any;
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
  return;
}

event shutdown => sub {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
  $kernel->refcount_decrement( $self->get_session_id, __PACKAGE__ );
  $kernel->post( $self->_http_alias, 'shutdown' );
  return;
};

event user => sub {
  my ($kernel,$self,$sender,$cmd) = @_[KERNEL,OBJECT,SENDER,ARG0];
  my $args;
  if ( ref $_[ARG1] eq 'HASH' ) {
     $args = $_[ARG1];
  }
  else {
     $args = { @_[ARG1..$#_] };
  }
  # check stuff
  # build url
  $args->{cmd} = lc $cmd;
  if ( $args->{cmd} =~ /^follow(ers|ing)$/ ) {
    $args->{url} = 'http://' . join '/', $self->url_path, 'user', 'show', $args->{user}, $args->{cmd};
  }
  else {
    $args->{url} = 'http://' . join '/', $self->url_path, 'user', $args->{cmd}, $args->{user};
  }
  warn $args->{url}, "\n";
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
  $kernel->post( 
    $self->_http_alias, 
    'request',
    '_response',
    GET( $args->{url} ),
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
     $args->{data} = $self->json->jsonToObj($json);
  }
  my $session = delete $args->{session};
  my $event   = delete $args->{event};
  $kernel->post( $session, $event, $args );
  $kernel->refcount_decrement( $session, __PACKAGE__ );
  return;
};

no MooseX::POE;

#__PACKAGE__->meta->make_immutable;

'Moooooooooooose!';
__END__
