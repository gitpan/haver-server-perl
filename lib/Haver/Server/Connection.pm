# Haver::Server::Connection,
# this creates a session, which represents the user...
# 
# Copyright (C) 2003 Dylan William Hardison.
#
# This module is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This module is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this module; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA

# TODO, write POD. Soon.
package Haver::Server::Connection;
use strict;
use Carp qw(croak confess carp cluck);

use POE qw(
	Wheel::ReadWrite
	Driver::SysRW
	Preprocessor
	Filter::Haver
);

use Haver::Protocol;
use Haver::Server::Globals qw( $Registry $Config );
use Haver::Server::Connection::Commands;
use Digest::SHA1 qw( sha1_base64 );

our $RELOAD = 1;

sub create {
	my ($class, @args) = @_;
	my $C = "Haver::Server::Connection::Commands";

	POE::Session->create(
		package_states => [ 
			$class => {
				# POE states
				'_start'    => '_start',
				'_stop'     => '_stop',
				'_default'  => '_default',
				
				
				# Wheel states
				'socket_input'  => 'socket_input',
				'socket_error'  => 'socket_error',
				'socket_flush'  => 'socket_flush',
				
				# Utility states
				'want'      => 'on_want',
				'cleanup'  => 'on_cleanup',
				'bye'     => 'on_bye',
				'warn'      => 'on_warn',
				'die'       => 'on_die',
				'accept'    => 'on_accept',
				'reject'    => 'on_reject',
				'askpass'   => 'on_askpass',
				'send_ping' => 'on_send_ping',
				'broadcast' => 'on_broadcast',

			},
			$C => $C->commands,
		],
		heap => {
		},
		args => \@args,
	);
}

sub _start {
	my ($heap, $session, $kernel, $socket, $address, $port ) = 
	@_[ HEAP,  SESSION,  KERNEL,  ARG0,    ARG1,     ARG2];
	$address = Socket::inet_ntoa($address);
	
    $kernel->post('Logger', 'note',  'Socket Birth');
	$kernel->post('Logger', 'note', "Connection from ${address}:$port");


	binmode $socket, ":utf8";
	my $sock = new POE::Wheel::ReadWrite(
		Handle       => $socket,
		Driver       => new POE::Driver::SysRW,
		Filter       => new POE::Filter::Haver,
		InputEvent   => 'socket_input',
		FlushedEvent => 'socket_flush',
		ErrorEvent   => 'socket_error',
	);


	my $timer = $kernel->alarm_set(
		'bye', 
		time + 20,
		'TIMEOUT',
	);

	%$heap = (
		timer       => $timer,
		ping        => undef,
		ping_time   => undef,
		socket      => $sock,
		address     => $address,
		port        => $port,
		shutdown    => 0,
		plonk       => 0,
		want        => undef,
		want_data   => undef, # called if CANT $WANT...
		user        => undef,
		uid         => undef,
		mode        => 'old',
	);

	$kernel->yield('want', 'VERSION',
		code => sub {
			$kernel->yield('bye', 'CANT VERSION');
		},
	);

}
sub _stop {
	my ($kernel, $heap, $session) = @_[KERNEL, HEAP, SESSION];

	my ($address, $port) = @$heap{qw(address port)};
    $kernel->call('Logger', 'note',  'Socket Death');
	$kernel->call('Logger', 'note', "Lost connection from ${address}:$port");
}
sub _default {
	my ($kernel, $heap, $event, $args) = @_[KERNEL, HEAP, ARG0, ARG1];


	if ($event =~ s/^cmd_//) {
		my $cmd = "cmd_$event";
		if (my $code = Haver::Server::Commands->can($cmd)) {
			$kernel->state($cmd, 'Haver::Server::Commands');
			@_[ARG0 .. $#_] = @{ $_[ARG1] };
			goto &$code;
		}
		$kernel->yield('warn', UCMD => $event);
	}
	$kernel->post('Logger', 'error', "Unknown event: $event");

	return 0;
}

sub socket_input {
	my ($kernel, $heap, $args) = @_[KERNEL, HEAP, ARG0];
	
	my @copy = @$args;
	foreach (@copy) {
		next unless defined;
		#my @foo = split(//, $_);
		#foreach my $c (@foo) {
			#$c = ord($c);
			#$c = "[$c]";
		#}
		#$_ = join('', @foo);
		s/\e/<ESC>/g;
		s/\r/<CR>/g;
		s/\n/<LF>/g;
		s/\t/<TAB>/g;
	}
	my $raw = join("\t", map { defined $_ ? $_ : '' } @copy);
	$kernel->post('Logger', 'raw', $raw);
	
	return if $heap->{plonk};
	return if $heap->{shutdown};
	if ($heap->{ping} && !$heap->{ping_time}) {
		$kernel->alarm_remove($heap->{ping});
		$heap->{ping} = $kernel->alarm_set(
			'send_ping',
			time + $Config->{Server}{PingTime});
	}

	my $want = 0;
	my $cmd = shift @$args;

	if ($heap->{want} and $cmd ne 'CANT') {
		if ($cmd eq $heap->{want}) {
			$want = 1;
			$heap->{want} = undef;
		} else {
			$kernel->yield('die', 'WANT', $heap->{want}, $cmd);
			return;
		}
	}

	if ($heap->{user} or $want) {
		$heap->{scope} = {
		};
		$kernel->yield("cmd_$cmd", $args);
	} else {
		$kernel->yield('die', 'SPEEDY');
	}
}
sub socket_flush {
	my ($kernel, $heap) = @_[KERNEL, HEAP];

	if ($heap->{shutdown}) {
		$heap->{socket} = undef;
	}
}
sub socket_error {
	my ($kernel, $heap, $operation, $errnum, $errstr) = @_[KERNEL, HEAP, ARG0..ARG3];

	$kernel->post('Logger', 'error', 
		"Socket generated $operation error ${errnum}: $errstr");

	$heap->{socket} = undef;
	$kernel->yield('cleanup', 'DISCON');
}


sub on_bye {
	my ($kernel, $heap, $session, @args) = @_[KERNEL, HEAP, SESSION, ARG0 .. $#_];
	return if $heap->{shutdown};

	$heap->{socket}->put(['BYE', @args]);
	$heap->{shutdown} = 1;
	$kernel->yield('cleanup', @args);
}

sub on_want {
	my ($kernel, $heap, $want, %opts) = @_[KERNEL, HEAP, ARG0 .. $#_];

	#$want =~ s/\W//g;
	#$want = uc $want;

	$kernel->post('Logger', 'note', "Want: $want");
	unless ($heap->{socket}) {
		my ($file, $line) = @_[CALLER_FILE,CALLER_LINE];
		$kernel->post('Logger', 'error', "on_want called with undefined socket at $file line $line!");
		return;
	}
	$heap->{want} = $want;
	delete $heap->{want_data}{code};

	foreach my $key (keys %opts) {
		$heap->{want_data}{$key} = $opts{$key};
	}

	my @args = $opts{args} ? @{$opts{args}} : ();
	$heap->{socket}->put(['WANT', $want, @args])
		unless delete $heap->{want_data}{no_send};
}
sub on_cleanup {
	my ($kernel, $heap, @args) = @_[KERNEL, HEAP, ARG0 .. $#_];

	if (!$heap->{cleanup}) {
		$kernel->call('Logger', 'note', 'Shutting down client session.');
		my $user = $heap->{user};
		my $uid  = $heap->{uid};
		$heap->{cleanup} = 1;
		$heap->{plonk} = 1;
		$heap->{user} = undef;
		$heap->{uid} = undef;
		
		$kernel->alarm_remove_all();
		if ($uid) {
			$Registry->remove('user', $uid);
			my @users = ();
			foreach my $chan ($user->list_vals('channel')) {
				$user->remove($chan);
				$chan->remove($user);
				push(@users, $chan->list_vals('user'));
			}
			my %users = map { ($_ => $_) } @users;
			my $msg = ['QUIT', $uid, @args];
			foreach my $u (values %users) {
				eval { $u->send($msg) };
			}
		}
		if ($user) {
			($heap->{port}, $heap->{address}) = $user->get('.port', '.address');
			$user->save if $user->password;
		}
	} else {
		$kernel->post('Logger', 'error', "Trying to run cleanup more than once! @args");
	}
}

sub on_die {
	my ($kernel, $heap, $err, @data) = @_[KERNEL, HEAP, ARG0 .. $#_];

	$heap->{socket}->put(['DIE', $err, @data]);
	$kernel->yield('bye', 'DIE');
}
sub on_warn {
	my ($kernel, $heap, $err, @data) = @_[KERNEL, HEAP, ARG0 .. $#_];

	$kernel->post('Logger', 'warn', "Warning $heap->{uid}: $err");
	$heap->{socket}->put(['WARN', $err, @data]);
}


sub on_accept {
	my ($kernel, $heap, $uid, $user) = @_[KERNEL, HEAP, ARG0, ARG1];

	$kernel->alarm_remove(delete $heap->{timer});
	$heap->{ping} = $kernel->alarm_set(
		'send_ping',
		time + $Config->{Server}{PingTime});
	$heap->{ping_time} = undef;
	


	$Registry->add($user);
	$heap->{user} = $user;
	$heap->{uid}  = $uid;
	my $addr = join('.', (split(/\./, $heap->{address}))[0,1,2]) . '.*';
	$user->set(
		version     => delete $heap->{want_data}{version},
		mode        => delete $heap->{want_data}{mode},
		address     => $addr,
		'.address'  => delete $heap->{address},
		'.port'     => delete $heap->{port},
	);
	$user->set_flags('version',  'lp');
	$user->set_flags('address',  'l');
	$user->set_flags('.address', 'l');
	$user->set_flags('.port', 'l');

	$heap->{socket}->put(['ACCEPT', $uid], ['LINE', $Config->{Server}{LineLimit}]);
}

sub on_reject {
	my ($kernel, $heap, $uid, $err) = @_[KERNEL, HEAP, ARG0, ARG1];

	$heap->{socket}->put(['REJECT', $uid, $err]);
	$kernel->yield('want', 'UID',
		code => sub {
			$kernel->yield('bye', 'CANT UID');
		},
		no_send => 1,
	);
}

sub on_askpass {
	my ($kernel, $heap, $uid, $user) = @_[KERNEL, HEAP, ARG0, ARG1];
	my $salt = sprintf("%f%x%o", rand(), time, $$);
	
	$kernel->yield('want', 'PASS',
		args    => [$salt],
		salt    => $salt,
		user    => $user,
		uid     => $uid,
		code    => sub {
			$kernel->yield('die', WANT => 'PASS');
		},
	);
}

sub on_send_ping {
	my ($kernel, $heap) = @_[KERNEL, HEAP];

	my $time = time;
	$heap->{socket}->put(['PING', $time]);
	
	$heap->{ping} = $kernel->alarm_set(
		'bye', time + $Config->{Server}{PingTime}, 'PING');
	$heap->{ping_time} = $time;

	$kernel->post('Logger', 'note', "Sending PING: $time");
}

sub on_broadcast {
	my ($kernel, $heap, $cid, $users, @rest) = @_[KERNEL, HEAP, ARG0 .. $#_];

	foreach my $u (@$users) {
		my $mode = $u->get('mode');

		if ($mode eq 'multi') {
			$u->send(['IN', $cid, @rest]);
		} elsif ($mode eq 'single') {
			$u->send(\@rest);
		}
	}
	
}

1;
