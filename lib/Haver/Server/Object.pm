# Haver::Server::Object - OO Channel/User/etc base class.
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
package Haver::Server::Object;
use strict;
use warnings;
use Carp;

use Fatal qw(:void open close opendir closedir);
use POE::Kernel             qw( $poe_kernel );
use Haver::Base;
use Haver::Preprocessor;

use YAML           (); # Load, Dump
use File::Basename (); # fileparse
use File::Spec;
use Scalar::Util   (); # weaken
use File::Path ();
# Subclass Haver::Savable
use base 'Haver::Savable';

use overload (
	'==' => 'equals',
	'""' => 'as_string',
	fallback => 1,
);

# Flags:
#  p = persistent : saved in userfile
#  l = locked     : user can't change

# Public variables:
our $RELOAD  = 1;
our $VERSION = "0.04";
our %Flags = (
	broadcast => 'p',
	public    => 'p',
	private   => 'p',
	secret    => 'l',
	flag      => '',
	attrib    => 'pl',
);
our %Types = (
	# '' => 'public',
	'+'  => 'broadcast',
	'.'  => 'private',
	'_'  => 'secret',
	'-'  => 'flag',
	'@'  => 'attrib',
);
our $IdPattern = qr/[a-z][a-z0-9_' -]+/;

# Private class variables:
# We use ||= instead of = so that this module may be reloaded.
my $ID        ||= 1;
my $StoreDir  ||= './store';


### Class methods.
## Validation methods
sub is_valid_tag {
	my ($me, $tag) = @_;

	my $word = $IdPattern;
	unless ($tag =~ /^$word\/$word$/) {
		return 1;
	} else {
		return 0;
	}
}

sub is_valid_id {
	my ($this, $uid) = @_;

	if (defined $uid && $uid =~ /^$IdPattern$/) {
		return 1;
	} else {
		return 0;
	}
}

sub field_type {
	my ($this, $f) = @_;
	my ($char) = $f =~ /^([^a-zA-Z0-9])/;

	if (defined $char) {
		return $Types{$char};
	} else {
		return 'public';
	}
}

sub store_dir {
	my ($class, $dir) = @_;
	ASSERT: not ref $class;

	if (@_ == 1) {
		return $StoreDir;
	} else {
		return $StoreDir = $dir;
	}
}

sub namespace { 'object'  } 


### Object methods
sub initialize {
	my ($me) = @_;

	$me->SUPER::initialize();

	$me->{_fields}    = {};
	$me->{_flags}     = {};
	$me->{id}       ||= $ID++;
	
	if (exists $me->{wheel}) {
		Scalar::Util::weaken($me->{wheel});
	}
	return $me;
}

## Helper methods for POE-ness.
sub post {
	my $me = shift;

	croak "Can not post. session id is not defined!" unless defined $me->{sid};
	$poe_kernel->post($me->{sid}, @_);
}

sub send {
	my $me = shift;
	
	croak "Can not send. Wheel undefined!" unless defined $me->{wheel};
	$me->{wheel}->put(@_);
}




## Accessor methods.
sub id {
	my ($me, $val) = @_;

	if (@_ == 2) {
		return $me->{id} = $val;
	} else {
		return $me->{id};
	}
}

sub filename {
	my ($me) = @_;
	return File::Spec->catfile($StoreDir, $me->namespace, $me->id);
}

sub directory {
	my ($me) = @_;

	return File::Spec->catdir($StoreDir, $me->namespace);
}

## Flag methods
sub get_flags {
	my ($me, $key) = @_;

	if (exists $me->{_flags}{$key}) {
		return $me->{_flags}{$key};
	} else {
		return $Flags{ $me->field_type($key) };
	}
}
sub set_flags {
	my ($me, $key, $value) = @_;
	$me->{_flags}{$key} = $value;
}

sub has_flags {
	my ($me, $key, $flags) = @_;
	
	for my $flag (split(//, $flags)) {
		unless ($me->has_flag($key, $flag)) {
			return 0;
		}
	}
	
	return 1;
}

sub has_flag {
	my ($me, $key, $flag) = @_;
	my $s = $me->get_flags($key);

	return undef unless defined $s;
	return index($s, $flag) != -1;
}

## Methods for accessing fields.
sub set {
	my ($me, @set) = @_;
	
	while (my ($k,$v) = splice(@set, 0, 2)) {
		$me->{_fields}{$k} = $v;
	}
}
sub get {
	my ($me, @keys) = @_;

	if (@keys <= 1) {
		return $me->{_fields}{$keys[0]};
	}
	my @values;
	
	foreach my $key (@keys) {
		push(@values, $me->{_fields}{$key});
	}

	return wantarray ? @values : \@values ;
}
sub has {
	my ($me, @keys) = @_;

	if (@keys <= 1) {
		return exists $me->{_fields}{$keys[0]};
	}
	
	foreach my $key (@keys) {
		unless (exists $me->{_fields}{$key}) {
			return undef;
		}
	}

	return 1;
}
sub del {
	my ($me, @keys) = @_;
	
	if (@keys <= 1) {
		return delete $me->{_fields}{$keys[0]};
	}
	
	foreach my $key (@keys) {
		delete $me->{_fields}{$key};
	}
	
	
	return 1;
}
sub list_fields {
	my ($me) = @_;
	return keys %{ $me->{_fields} };
}



sub _save_data {
	my ($me) = @_;
	my (%fields, %flags);
	my %data = (
		Class  => ref($me),
		ID     => $me->id,
		NS     => $me->namespace,
		fields => \%fields,
		flags => \%flags
	);

	foreach my $f ($me->list_fields) {
		if ($me->has_flag($f, 'p')) {
			$fields{$f} = $me->{_fields}{$f};
		}
	}
	%flags = %{ $me->{_flags} };

	File::Path::mkpath($me->directory);
	return \%data;
}

sub _load_data {
	my ($me, $data) = @_;
	
	no warnings;
	ASSERT: $data->{ID}    eq $me->id;
	ASSERT: $data->{NS}    eq $me->namespace;
	ASSERT: $data->{Class} eq ref($me);
	use warnings;

	$me->{_fields} = delete $data->{fields};
	$me->{_flags}  = delete $data->{flags};

	1;
}

## Operator overload methods
sub equals {
	my ($me, $what) = @_;
	return undef unless $what->can('namespace') && $what->can('id');
	return (($me->namespace eq $what->namespace) and ($me->id eq $what->id));
}

sub as_string {
	my ($me) = @_;

	return $me->namespace . '/' . $me->id;
}

1;
=head1 NAME

Haver::Server::Object - Base class for Users and Channels.

=head1 SYNOPSIS

  use Haver::Server::Object;
  # FIXME.

=head1 DESCRIPTION

FIXME


=head1 METHODS
	
FIXME

=head1 SEE ALSO

L<Haver::Server::User>, L<Haver::Server::Channel>.

=head1 AUTHOR

Dylan William Hardison, E<lt>dylanwh@tampabay.rr.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2003-2004 by Dylan William Hardison

This module is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This module is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this module; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

=cut
