package POE::Component::Github::URL::Users;

use strict;
use warnings;
use vars qw($VERSION);

$VERSION = '0.02';

use Moose;
use Moose::Util::TypeConstraints;

use URI::Escape;

with 'POE::Component::Github::URL::Role';

has cmd => (
  is       => 'ro',
  isa      => enum([qw(
		search 
		show 
		followers 
		following 
		update 
		follow 
		unfollow 
		pub_keys 
		add_key 
		remove_key 
		emails 
		add_email 
		remove_email
              )]),
  required => 1,
);

has user => (
  is       => 'ro',
  isa      => 'Str',
  default  => '',
);

sub url {
  my $self = shift;
  
}

no Moose;

1;
__END__
