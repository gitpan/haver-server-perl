# Haver::Server::Object::Index - Index of objects.
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
package Haver::Server::Object::Index;
use strict;
use warnings;
use Carp;


our $VERSION = '0.04';
our $RELOAD  = 1;

sub namespace {
	return 'container';
}

sub has_namespace {
	my ($me, $ns) = @_;
	return exists $me->{".$ns"};
}

sub namespaces {
	my ($me) = @_;
	my @ns = ();

	@ns = grep(s/^\.//, keys %{ $me });

	return wantarray ? @ns : \@ns;
}

sub add {
	my ($me, $object) = @_;
	my $id = $object->id;
	my $ns = $object->namespace;
	
	if (not($me->contains($ns, $id)) && $me->can_contain($object)) {
		$me->{".$ns"}{$id} = $object;
		$me->{".$ns"}{$id}
	} else {
		return undef;
	}
}

sub fetch {
	my ($me, $ns, $id) = @_;
	if (@_ != 3) {
		croak "fetch must be called with exactly three arguments!";
	}

	return $me->{".$ns"}{$id} if $me->contains($ns, $id);
}

sub contains {
	my ($me, $ns, $id) = @_;
	if (@_ != 3) {
		croak "contains must be called with exactly three arguments!";
	}
	
	delete $me->{".$ns"}{$id} unless defined $me->{".$ns"}{$id};
	return exists $me->{".$ns"}{$id};
}

sub remove {
	my $me = shift;
	my ($ns, $id);
	
	if (@_ == 1 && ref $_[0]) {
		my $o = $_[0];
		$ns = $o->namespace;
		$id = $o->id;
	} elsif (@_ == 2) {
		($ns, $id) = @_;
	} else {
		die "Wrong number of arguments.";
	}
	delete $me->{".$ns"}{$id};
}

sub list_ids {
	my ($me, $ns) = @_;
	my $h = $me->{".$ns"};

	wantarray ? keys %$h : [ keys %$h ];
}
sub list_vals {
	my ($me, $ns) = @_;
	my $h = $me->{".$ns"};

	wantarray ? values %$h : [ values %$h ];
}
sub can_contain {
	# Can contain anything, really.
	1; 
}

1;
