package POE::Component::Github::URL::Role;

use strict;
use warnings;
use vars qw($VERSION);

$VERSION = '0.02';

use Moose::Role;

# login
has 'login'  => ( is => 'ro', isa => 'Str', default => '' );
has 'token' => ( is => 'ro', isa => 'Str', default => '' );

# api
has '_api_url' => ( is => 'ro', default => 'github.com/api/v2/json/');
has '_scheme'  => ( is => 'ro', default => 'http://');
has '_auth'    => ( is => 'ro', default => '');

no Moose::Role;

1;
__END__
