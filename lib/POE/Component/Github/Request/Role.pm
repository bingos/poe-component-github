package POE::Component::Github::Request::Role;

use strict;
use warnings;
use vars qw($VERSION);

$VERSION = '0.02';

use Moose::Role;

# login
has 'login'  => ( is => 'ro', isa => 'Str', default => '' );
has 'token' => ( is => 'ro', isa => 'Str', default => '' );

# api
has 'api_url' => ( is => 'ro', default => 'github.com/api/v2/json/');
has 'scheme'  => ( is => 'ro', default => 'http://');
has 'auth'    => ( is => 'ro', default => '');
has 'values'  => ( is => 'ro', default => sub { { } } );

no Moose::Role;

1;
__END__
