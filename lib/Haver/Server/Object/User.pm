# Haver::Server::Object::User - OO User object thing.
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
package Haver::Server::Object::User;
use strict;
use warnings;
use Carp;

use Haver::Preprocessor;
use Haver::Server::Object;
use Haver::Server::Object::Index;
use Haver::Server::Globals qw( $Store $Registry );

use base qw( Haver::Server::Object Haver::Server::Object::Index );

use Scalar::Util qw( weaken );

our $VERSION = '0.04';


sub initialize {
	my ($me) = @_;

	$me->SUPER::initialize();
	$me->{_access}   = {};

	$me->set(
		role => 'user',
	);
	$me->set_flags('role', 'lp');


	$me->{password} = '';
}

sub may {
	my ($me, $act, %arg) = @_;
	
	if (ref $act) {
		foreach my $a (@$act) {
			$me->may($a, %arg) or return undef;
		}
		return 1;
	}

	if ($arg{scope}) {
		my $a = "$arg{scope}:$act";
		return $me->{_access}{$a} if exists $me->{_access}{$a};
	}
	return $me->{_access}{$act} if exists $me->{_access}{$act};

	my $role = do {
		if ($arg{scope} && $me->has("$arg{scope}:role")) {
			$me->get("$arg{scope}:role");
		} else {
			$me->get('role');
		}
	};
	
	return $Store->{Roles}{$role}{$act} if exists $Store->{Roles}{$role}{$act};
	return undef;
}

sub grant {
	my ($me, $act, %arg) = @_;
	my $key = $arg{scope} ? "$arg{scope}:$act" : $act;
	
	$me->{_access}{$key} = 1;
}

sub ungrant {
	my ($me, $act, %arg) = @_;
	
	my $key = $arg{scope} ? "$arg{scope}:$act" : $act;
	delete $me->{_access}{$key};
}

sub revoke {
	my ($me, $act, %arg) = @_;

	my $key = $arg{scope} ? "$arg{scope}:$act" : $act;
	$me->{_access}{$key} = 0;
}


sub _save_data {
	my ($me) = @_;
	my $data = $me->SUPER::_save_data();

	
	$data->{password} = $me->{password};
	$data->{access} = $me->{_access};

	return $data;
}

sub _load_data {
	my ($me, $data) = @_;
	$me->SUPER::_load_data($data);
	$me->{_access} = $data->{access};
	$me->{password} = $data->{password};

	return 1;
}


sub password {
	my ($me, $val) = @_;
	if (@_ == 2) {
		return $me->{password} = $val;
	} else {
		return $me->{password};
	}
}

sub namespace {
	'user'
}


1;
__END__
=head1 NAME

Haver::Server::Object::User - Object representation of a user.

=head1 SYNOPSIS



=head1 DESCRIPTION

This module is a representation of a user. It's rather pointless, but it gives
you a warm fuzzy feeling. In the future, it might store the users in a database or something.


