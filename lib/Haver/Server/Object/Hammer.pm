# Haver::Server::Object::Hammer - OO Hammer object thing.
# 
# Copyright (C) 2004 Dylan William Hardison
#
# This module is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This module is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this module; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
package Haver::Server::Object::Hammer;
use strict;
use warnings;
use Carp;


use Haver::Server::Object;
use base qw( Haver::Server::Object::Grantable );

our $VERSION = '0.04';
our $AUTOLOAD;


sub namespace { 'hammer' }

sub initialize {
	my ($me) = shift;

	$me->SUPER::initialize(@_);
	$me->{user} or croak "Need user object!";

	$me->{home}   ||= 'object/limbo';
	$me->{owner}  ||= 'object/nobody';
}

sub has {
	my ($me, @keys) = @_;

	return $me->SUPER::has(@keys) || $me->{user}->has(@keys);
}

sub get {
	my ($me, @keys) = @_;
	my @values;

	foreach my $k (@keys) {
		push(@values, $me->SUPER::get($k) || $me->{user}->get($k));
	}
	
	return @values;
}


BEGIN { 
	no strict 'refs';
	foreach my $sub (qw( home owner user )) {
		*{$sub} = sub {
			my ($me, $val) = @_;
			if (@_ == 2) {
				return $me->{$sub} = $val;
			} else {
				return $me->{$sub};
			}
		};
	}
}



#sub AUTOLOAD {
#	my $me = shift;
#	my $method = (split("::", $AUTOLOAD))[-1];
#
#	$me->{user}->$method(@_);
#}

1;
__END__
=head1 NAME

Haver::Server::Object::Hammer - Object representation of a user.

=head1 SYNOPSIS

  use Haver::Server::Object::Hammer;
  my %opts = (); # No options at this time...
  my $uid  = 'rob';
  a
  my $user = new Haver::Server::Object::Hammer($uid, %opts);
  
  $user->uid eq $uid; # True
  $user->set(nick => "Roberto");
  $user->set(away => "Roberto isn't here.");
  $user->get('nick') eq 'Roberto'; # True
  my ($nick, $away) = $user->get('nick', 'away'); # Obvious...
  my $array_ref = $user->get('nick', 'away'); # Like above, but a arrayref.

  $user->unset('nick', 'away'); # unset one or more items.

  my @fields = $user->keys; # Returns all fields.

  $user->add_cid($cid);
  $user->remove_cid($cid);

=head1 DESCRIPTION

This module is a representation of a user. It's rather pointless, but it gives
you a warm fuzzy feeling. In the future, it might store the users in a database or something.


