# Haver::Server::Object::Channel - OO representation of a channel.
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
package Haver::Server::Object::Channel;
use strict;
use warnings;

use Haver::Server::Object;
use Haver::Server::Object::Index;
use base qw( Haver::Server::Object Haver::Server::Object::Index );

our $VERSION = '0.05';

sub namespace {
	return 'channel';
}

sub can_contain {
	my ($me, $obj) = @_;
	
	!$obj->isa(__PACKAGE__);
}

sub send {
	my $me = shift;

	foreach my $user ($me->list_vals('user')) {
		$user->send(@_);
	}
}

1;
