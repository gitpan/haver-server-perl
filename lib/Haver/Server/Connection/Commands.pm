# Haver::Server::Connection::Commands,
# Commands for Haver::Server::Connection.
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
package Haver::Server::Connection::Commands;
use strict;
#use warnings;

use Carp;
use POE;
use POE::Preprocessor;

use Haver::Server::Globals qw( $Registry $Config );
use Haver::Preprocessor;
use Digest::SHA1           qw(sha1_base64);
use Haver::Misc ();

our $VERSION = 0.02;
our $RELOAD = 1;
our @Commands = qw(
	UID PASS VERSION CANT
	MSG  PMSG
	JOIN PART GO QUIT MODE
	USERS CHANS PONG
	RELOAD LOAD PANG
	KILL REHASH
	IN ON TIME GMTIME
	GRANT REVOKE CLEAR
);

macro assert_channel(myCid) {
	return unless defined myCid;
	($poe_kernel->yield('warn', CID_INVALID => myCid), return)
		unless Haver::Server::Object::Channel->is_valid_id(myCid);

	($poe_kernel->yield('warn', CID_NOT_FOUND => myCid), return)
		unless $Registry->contains('channel', myCid);
}
macro assert_user(myUid) {
	return unless defined myUid;

	($poe_kernel->yield('warn', UID_INVALID => myUid), return)
		unless Haver::Server::Object::User->is_valid_id(myUid);
	($poe_kernel->yield('warn', UID_NOT_FOUND => myUid), return)
		unless myUid eq '.' or $Registry->contains('user', myUid);
}

sub commands {
	my ($this) = @_;
	
	return { map {("cmd_$_" => "cmd_$_")} @Commands };
}


sub cmd_UID {
	my ($kernel, $heap, $args, $ses) = @_[KERNEL, HEAP, ARG0, SESSION];
	my $uid = $args->[0];
	
	return if $heap->{uid};

	if ($uid eq '.') {
		$kernel->yield('reject', $uid, 'UID_RESERVED');
		return;
	}
	
	unless (Haver::Server::Object::User->is_valid_id($uid)) {
		$kernel->yield('reject', $uid, 'UID_INVALID');
		return;
	}
	
	my $user = new Haver::Server::Object::User(
		id    => $uid,
		sid   => $ses->ID,
		wheel => $heap->{socket},
	);

	if (not $Registry->contains(user => $uid)) {
		if ($user->load) {
			$kernel->post('Logger', 'login', "Loaded okay");
			if ($user->password) {
			$kernel->post('Logger', 'login', "Asking pass");
				$kernel->yield('askpass', $uid, $user);
			} else {
				$kernel->post('Logger', 'login', "Accepting it");
				$kernel->yield('accept', $uid, $user);
			}
		} else {
			$kernel->yield('accept', $uid, $user);
			$kernel->post('Logger', 'login', "Accepting it");
		}
	} else {
		$kernel->yield('reject', $uid, 'UID_IN_USE');
	}
}
sub cmd_PASS {
	my ($kernel, $heap, $args) = @_[KERNEL, HEAP, ARG0];
	my $uid    =  delete $heap->{want_data}{uid};
	my $user   = delete $heap->{want_data}{user};
	my $salt   = delete $heap->{want_data}{salt};
	my $result = $args->[0];

	if ($result eq sha1_base64($user->password . $salt)) {
		$kernel->yield('accept', $uid, $user);
	} else {
		$kernel->yield('reject', $uid, 'PASS_INVALID');
	}
	
}

sub cmd_VERSION {
	my ($kernel, $heap, $args) = @_[KERNEL, HEAP, ARG0];
	my $ver = $args->[0];

	if ($ver) {
		$kernel->yield('want', 'MODE',
			version => $ver,
			code => sub {
				$kernel->yield('die', 'WANT', 'UID');
			},
		);
	} else {
		$kernel->yield('die', BADVER => $ver);
	}
}

sub cmd_MODE {
	my ($kernel, $heap, $args) = @_[KERNEL, HEAP, ARG0];
	my $mode = $args->[0];
	
	return if $heap->{uid};

	if ($mode eq 'multi' or $mode eq 'single') {
		$kernel->yield('want', 'UID',
			mode  => $mode,
			code => sub {
				$kernel->yield('die', 'WANT', 'MODE');
			},
		);
	} else {
		$kernel->yield('die', UNKNOWN_MODE => $mode);
	}
}


sub cmd_CANT {
	my ($kernel, $heap, $args) = @_[KERNEL, HEAP, ARG0];
	my $want = $args->[0];
	
	if ($want eq $heap->{want}) {
		if (my $code = delete $heap->{want_data}{code}) {
			$code->($kernel, $heap);
		}
		$heap->{want} = undef;
	} else {
		$kernel->yield('die', CANT_WRONG => $want);
	}
}

sub cmd_MSG {
	my ($kernel, $heap, $args) = @_[KERNEL, HEAP, ARG0];
	my ($type, $msg) = @$args;
	my $user = $heap->{user};
	my $cid = do {
		# Check the scope only if in multi mode.
		if ($user->get('mode') eq 'multi') {
			$heap->{scope}{chan} || $heap->{chan};
		} else {
			if ($heap->{scope}{chan}) {
				# ERROR: SYNTAX
				$kernel->yield('die', 'SYNTAX');
				return;
			}
			$heap->{chan};
		}
	};

	if (not defined $cid) {
		# ERROR: NO_CHAN
		$kernel->yield('warn', 'NO_CHAN');
		return;
	}
	$kernel->post('Logger', 'debug', "Got message from $heap->{uid}, sending to $cid");
	return unless check_cid($cid);
	
	my $chan = $Registry->fetch('channel', $cid);
	my @msg = ('MSG', $heap->{uid}, $type, $msg);
	my $users = $chan->list_vals('user');
	$kernel->yield('broadcast', $cid, $users, @msg);
}


sub cmd_PMSG {
	my ($kernel, $heap, $args) = @_[KERNEL, HEAP, ARG0];
	my ($target_uid, $type, $msg) = @$args;
	my $user       = $heap->{user};
	my $uid        = $heap->{uid};

	return unless check_uid($target_uid);
	
	my $target = $Registry->fetch('user', $target_uid);

	$target->send(['PMSG', $uid, $type, $msg]);
}

sub cmd_JOIN {
	my ($kernel, $heap, $args, $single) = @_[KERNEL, HEAP, ARG0, ARG1];
	my $cid  = $args->[0];
	my $user = $heap->{user};
	my $uid  = $heap->{uid};
	
	if ($user->get('mode') eq 'single' and not $single) {
		$kernel->yield('die', UCMD => 'JOIN');
		return;
	}
	
	return unless check_cid($cid);
	#{#% assert_channel $cid %}

	unless ($user->contains('channel', $cid)) {
		my $chan = $Registry->fetch('channel', $cid);
		$chan->add($user);
		$user->add($chan);
		my $users = $chan->list_vals('user');
		$kernel->yield('broadcast', $cid, $users, 'JOIN', $heap->{uid});
	} else {
		$kernel->yield('warn', ALREADY_JOINED => $cid);
	}
}
sub cmd_PART {
	my ($kernel, $heap, $args, $single) = @_[KERNEL, HEAP, ARG0, ARG1];
	my $cid = $args->[0];
	my $user = $heap->{user};
	my $uid  = $heap->{uid};

	if ($user->get('mode') eq 'single' and not $single) {
		$kernel->yield('die', UCMD => 'PART');
		return;
	}
	
	#{#% assert_channel $cid %}
	return unless check_cid($cid);

	
	if ($user->contains('channel', $cid)) {
		my $chan = $Registry->fetch('channel', $cid);
		my $users = $chan->list_vals('user');
		$kernel->yield('broadcast', $cid, $users, 'PART', $heap->{uid});

		$chan->remove($user);
		$user->remove($chan);
	} else {
		$kernel->yield('warn', NOT_JOINED_PART => $cid);
	}
}

sub cmd_GO {
	my ($kernel, $heap, $session, $args) = @_[KERNEL, HEAP, SESSION, ARG0];
	my $cid = $args->[0];

	if ($heap->{user}->get('mode') eq 'multi') {
		$kernel->yield('die', UCMD => 'GO');
		return;
	}
	
	if ($heap->{chan}) {
		$kernel->call($session, 'cmd_PART', [$heap->{chan}], 'single');
	}
	$kernel->call($session, 'cmd_JOIN', [$cid], 'single');

	if ($heap->{user}->contains('channel', $cid)) {
		$heap->{socket}->put(['WENT', $cid]);
		$heap->{chan} = $cid;
	}
}




sub cmd_QUIT {
	my ($kernel, $heap) = @_[KERNEL, HEAP];

	$kernel->yield('bye', 'ACTIVE');
}


sub cmd_CHANS {
	my ($kernel, $heap) = @_[KERNEL, HEAP];

	
	$heap->{socket}->put(['CHANS', $Registry->list_ids('channel')]);
}
sub cmd_USERS {
	my ($kernel, $heap, $args) = @_[KERNEL, HEAP, ARG0];
	my $cid = $heap->{scope}{chan} || $heap->{chan};
	my $user = $heap->{user};
	my $uid  = $heap->{uid};

	my $chan;
	if ($cid ne '*') {
		#{#% assert_channel $cid %}
		return unless check_cid($cid);
		$chan = $Registry->fetch('channel', $cid);
	} else {
		$chan = $Registry;
	}


	my @msg = ('USERS', $chan->list_ids('user'));
	if ($user->get('mode') eq 'multi' or $heap->{scope}{chan}) {
		unshift(@msg, 'IN', $cid);
	}
	$heap->{socket}->put(\@msg);
}




# QUIT

# PONG($data)
sub cmd_PONG {
	my ($kernel, $heap, $args) = @_[KERNEL, HEAP, ARG0];
	my $time = $args->[0];
	if (defined $heap->{ping_time}) {
		if ($time eq $heap->{ping_time}) {
			$kernel->alarm_remove($heap->{ping});
			$heap->{ping} = $kernel->alarm_set('send_ping',
				time + $Config->{Server}{PingTime});
			$heap->{ping_time} = undef;
		} else {
			$kernel->yield('bye', 'BAD PING');
		}
	} else {
		$kernel->yield('die', 'UNEXPECTED_PONG');
	}
}

# PONG($data)
sub cmd_PANG {
	my ($kernel, $heap, $args) = @_[KERNEL, HEAP, ARG0];
	my $time = $args->[0];

	unless ($heap->{user}->may('pang')) {
		$kernel->yield('warn', ACCESS => 'PANG');
		return;
	}

	
	$kernel->alarm_remove(delete $heap->{ping});
	delete $heap->{ping_time};
}

sub cmd_RELOAD {
	my ($kernel, $heap, $args) = @_[KERNEL, HEAP, ARG0];
	my $user = $heap->{user};

	unless ($user->may('reload')) {
		$kernel->yield('warn', ACCESS => 'RELOAD');
		return;
	}

	my @mods = Haver::Reload->reload;
	foreach my $mod (@mods) {
		$kernel->post('Logger', 'note', "Reloaded $mod");
	}
}

sub cmd_LOAD {
	my ($kernel, $heap, $args) = @_[KERNEL, HEAP, ARG0];
	my $user = $heap->{user};
	my $mod  = $args->[0];

	unless ($user->may('load')) {
		$kernel->yield('warn', ACCESS => 'LOAD');
		return;
	}

	Haver::Reload->load($mod);
}

sub cmd_KILL {
	my ($kernel, $heap, $args) = @_[KERNEL, HEAP, ARG0];
	my $user   = $heap->{user};
	my $victim = $args->[0];


	#{#% assert_user $victim %};
	return unless check_uid($victim);
	return unless check_cmd_access($user, 'kill');

	my $v = $Registry->fetch('user', $victim);
	
	
	$kernel->post($v->{sid}, 'bye', 'KILL', $heap->{uid});
}

sub cmd_REHASH {
	my ($kernel, $heap, $args) = @_[KERNEL, HEAP, ARG0];
	my $user   = $heap->{user};
	my $victim = $args->[0];

	unless ($user->may('rehash')) {
		$kernel->yield('warn', ACCESS => 'REHASH');
		return;
	}
	$Config->reload;
}

sub cmd_IN {
	my ($kernel, $heap, $session, $args) = @_[KERNEL, HEAP, SESSION, ARG0];
	my $cid = shift @$args;
	my $cmd = shift @$args;
	$heap->{scope}{chan} = $cid;
	$kernel->call($session, "cmd_$cmd", $args);
	delete $heap->{scope}{chan};
}

sub cmd_ON {
	my ($kernel, $heap, $session, $args) = @_[KERNEL, HEAP, SESSION, ARG0];
	my $uid = shift @$args;
	my $cmd = shift @$args;
	$heap->{scope}{user} = $uid;
	$kernel->call($session, "cmd_$cmd", $args);
	delete $heap->{scope}{user};
}

sub cmd_GRANT {
	my ($kernel, $heap, $args) = @_[KERNEL, HEAP, ARG0];
	my ($uid, $act) = @$args;
	my $user = $heap->{user};
	my @scope = ();
	
	if (exists $heap->{scope}) {
		@scope = (scope => $heap->{scope});
	}

	#{#% assert_user $uid %}
	return unless check_uid($uid);
	return unless check_cmd_access($user, 'revoke',
		scope => $heap->{scope});


	my $u = $Registry->fetch('user', $uid);

	$u->grant($act, @scope);

	my @msg = ();
	if (exists $heap->{scope}) {
		@msg = ('IN', $heap->{scope});
	}
	
	$heap->{socket}->put([@msg, 'GRANT', $uid, $act]);
}


sub cmd_REVOKE {
	my ($kernel, $heap, $args) = @_[KERNEL, HEAP, ARG0];
	my $user = $heap->{user};
	my ($uid, $act) = @$args;
	my @scope = ();
	
	#{#% assert_user $uid %}
	return unless check_uid($uid);
	return unless check_cmd_access($user, 'revoke',
		scope => $heap->{scope});

	my $u = $Registry->fetch('user', $uid);

	$u->revoke($act, @scope);

	my @msg = ();
	if (exists $heap->{scope}) {
		@msg = ('IN', $heap->{scope});
	}
	
	$heap->{socket}->put([@msg, 'REVOKE', $uid, $act]);
}

sub cmd_CLEAR {
	my ($kernel, $heap, $args) = @_[KERNEL, HEAP, ARG0];
	my ($uid, $act) = @$args;
	my $user = $heap->{user};
	my @scope = ();
	
	if (exists $heap->{scope}) {
		@scope = (scope => $heap->{scope});
	}

	return unless check_uid($uid);
	return unless check_cmd_access($user, 'clear', @scope);

	my $u = $Registry->fetch('user', $uid);

	$u->ungrant($act, @scope);

	my @msg = ();
	if (exists $heap->{scope}) {
		@msg = ('IN', $heap->{scope});
	}
	
	$heap->{socket}->put([@msg, 'UNGRANT', $uid, $act]);
}

sub cmd_TIME {
	my ($kernel, $heap, $args) = @_[KERNEL, HEAP, ARG0];

	$heap->{socket}->put(['TIME', Haver::Misc::format_datetime(time)]);
}

sub cmd_GMTIME {
	my ($kernel, $heap, $args) = @_[KERNEL, HEAP, ARG0];

	$heap->{socket}->put(['GMTIME', 'unknown']);
}

sub cmd_SET {
	my ($kernel, $heap, $args) = @_[KERNEL, HEAP, ARG0];
	return;
	my ($tag, $key, $value) = @$args;
	my $user = $heap->{user};
	my $targ = tag_to_object($user, $tag) or return;
	my $type = Haver::Server::Object->field_type($key);



	
	$targ->set($key => $value);
}

sub cmd_GET {
	my ($kernel, $heap, $args) = @_[KERNEL, HEAP, ARG0];
	return;
	my ($tag, $key) = @$args;
	my $user = $heap->{user};
	my $targ = tag_to_object($user, $tag) or return;
	
	my $val = $targ->get($key);
	
	$heap->{socket}->put(['RET', $tag, $val]);

}

sub tag_to_object {
	my ($user, $tag) = @_;

	unless ($tag eq '.' or Haver::Server::Object->is_valid_tag($tag)) {
		$poe_kernel->yield('warn', TAG_INVALID => $tag);
		return undef;
	}

	if ($tag eq '.') {
		return $user;
	} else {
		my $targ;
		my ($ns, $id) = split('/', $tag, 2);
		unless ($Registry->has_namespace($ns)) {
			$poe_kernel->yield('warn', NS_NOT_FOUND => $ns);
			return undef;
		}
		unless ($targ = $Registry->fetch($ns, $id)) {
			$poe_kernel->yield('warn', TAG_NOT_FOUND => $tag);
			return undef;
		}
		return $targ;
	}
}

sub check_cmd_access {
	my ($user, $cmd, %arg) = @_;

	unless ($user->may($cmd, %arg)) {
		$poe_kernel->yield('warn', ACCESS => uc($cmd));
		return undef;
	}

	return 1;
}


sub check_uid {
	my $uid = shift;
	
	return undef unless defined $uid;

	unless (Haver::Server::Object::User->is_valid_id($uid)) {
		$poe_kernel->yield('warn', UID_INVALID => $uid);
		return undef;
	}
	
	unless ($uid eq '.' or $Registry->contains('user', $uid)) {
		$poe_kernel->yield('warn', UID_NOT_FOUND => $uid);
		return undef;
	}

	return 1;
}

sub check_cid {
	my $cid = shift;
	return undef unless defined $cid;
	
	unless (Haver::Server::Object::Channel->is_valid_id($cid)) {
		$poe_kernel->yield('warn', CID_INVALID => $cid);
		return undef;
	}

	unless ($Registry->contains('channel', $cid)) {
		$poe_kernel->yield('warn', CID_NOT_FOUND => $cid);
		return undef;
	}

	return 1;
}

1;
