# Haver::Server::Registry - Index for users, channels, etc.
# 
# Copyright (C) 2003 Dylan William Hardison
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
package Haver::Server::Registry;
use strict;
#use warnings;

use Haver::Singleton;
use Haver::Server::Object::Index;
use Haver::Server::Globals qw( %Feature );

use base qw( Haver::Singleton Haver::Server::Object::Index );
use POE;

our $VERSION = '0.03';
our $RELOAD = 1;

sub initialize {
	my ($me) = @_;
	POE::Session->create(
		object_states => [
			$me => {
				_start => 'on_start',
				_stop  => 'on_stop',
				map { ($_ => "on_$_") } qw(
					spoof
				),
			},
		],
	);
}


sub resolve {
	my ($me, $tag) = @_;
	my ($ns, $id) = split('/', $tag, 2);
	return undef unless defined $ns and defined $id;

	return $me->fetch($ns, $id);
}

sub on_spoof {
	my ($me, $kernel, $heap, $args) = @_[OBJECT, KERNEL, HEAP, ARG0];
	my ($targ, $msg) = @$args;

	if (my $user = $me->resolve($targ)) {
		$user->send($msg);
	}
}


sub on_start {
	my ($me, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
	warn "Registry starts.\n";
	$kernel->alias_set('Registry');

	#if ($Feature{IKC}) {
	#}
}

sub on_stop {
	my ($me, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
	warn "Registry stops.\n"
}

1;
