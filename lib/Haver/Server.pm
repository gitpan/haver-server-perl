# Haver::Server - Haver server daemon.
# 
# Copyright (C) 2003-2004 Dylan William Hardison
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
package Haver::Server;
use strict;
use open ":utf8";


use Data::Dumper;
#use IO::Poll;
use POE;

use Haver::Server::Globals qw( $Store $Registry %Feature $Config );
use Haver::Server::Listener;
use Haver::Server::Registry;
use Haver::Server::Object::Channel;
use Haver::Server::Object::User;
use Haver::Server::Object::Index;

use Haver::Preprocessor;

use Haver::Config;
use Haver::Logger;
use Haver::Reload;


our $VERSION = 0.06;


sub boot {
	my ($this, %opts) = @_;
	$|++;

	ASSERT: $opts{confdir};
	ASSERT: $opts{datadir};

	Haver::Server::Globals->init(
		Config   => new Haver::Config(
			file => "$opts{confdir}/config.yml",
			default => {
				IKC => {
					Host => 'localhost',
					Name => 'HaverServer',
					Port => 4040,
				},
				Logs => {},
				Server => {
					LineLimit => 2048,
					PingTime  => 60,
					Port => 7071,
				},
			},
		),
		Store    => new Haver::Config(
			file => "$opts{datadir}/store.yml",
			default => {
				Channels => [qw( lobby basement )],
				Roles => {
					admin => {
						speak => 1,
						kill  => 1,
						reload => 1,
					},
				},
			},
		),
		Registry => instance Haver::Server::Registry,
	);
	
	eval {
		require  POE::Component::IKC::Server;
		import  POE::Component::IKC::Server;
	};
	unless ($@) {
		create_ikc_server(
			ip    => $Config->{IKC}{Host} || 'localhost', 
			port  => $Config->{IKC}{Port} || '4040',
			name  => $Config->{IKC}{Name} || 'HaverServer',
		);
		$Feature{IKC} = 1;
	}
	

	Haver::Reload->init;
	$Config->{Server}{PingTime} ||= 60;
	Haver::Server::Object->store_dir( "$opts{datadir}/store" );


	foreach my $cid (@{ $Store->{Channels} }) {
		my $chan = new Haver::Server::Object::Channel(id => $cid);
		eval { $chan->load };
		if ($@) {
			warn "Can't load $cid.\n$@";
		}
		$chan->set(_perm => 1);
		$Registry->add($chan);
	}

	
	$this->create;
	$poe_kernel->run();
}
sub create {
	my ($class) = @_;
	POE::Session->create(
		package_states => [
			$class => [
				'_start',
				'_stop',
				'interrupt',
				'die',
				'shutdown',
			]
		],
		heap => {},
	);
}

sub _start {
	my ($kernel, $heap) = @_[KERNEL, HEAP];
	my $port = $Config->{Server}{Port} || 7070;
	
	print "Server starts.\n";
	create Haver::Logger (
		levels => $Config->{Logs},
	);
	create Haver::Server::Listener (
		port => $port
	);

		$poe_kernel->post('IKC', 'publish', 'Registry',
			[qw( spoof )]);

	
	$kernel->sig('INT' => 'intterrupt');
	$kernel->sig('DIE' => 'die');
}
sub _stop {
	print "Server stops.\n";

	my @chans;
	$Store->{Channels} = \@chans;

	foreach my $chan ($Registry->list_vals('channel')) {
		if ($chan->has('_perm')) {
			push(@chans, $chan->id);
			$chan->save;
		}
	}
	
	$Store->save;
	$Config->save;
}

sub die {
	print "Got DIE\n";
}

sub interrupt {
	print "Got INT\n";
}
sub shutdown {
}


1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Haver::Server - Haver chat server.

=head1 SYNOPSIS

  use Haver::Server;
  blah blah blah

=head1 DESCRIPTION

Haver::Server is the unified interface for the entire Haver chat server
collection of modules. haverd.pl is just a small wrapper around
this module. This module requires a lot more documentation than I
can produce at this time, so I will just ramble on about how, in general,
to use it.

The most basic usage is to say perl
C<-MHaver::Server -e'Haver::Server-E<gt>boot(option =E<gt> "value", etc =E<gt> "foo")>

There are a number of options, such as bindaddr, port, ikc_port, ikc_bindaddr,
which I will have to explain later. Right now the interface may change or be completely
different. I'm not entirely sure this module shouldn't be under the POE::Component::Server::
namespace, as the client portion of haver is. I do really like the current namespace,
but this being an open source projct, perhaps I will not get my way.

I do not think Haver::Server will replace IRC, IRC has some nice features that I have no wont
to implement in haver yet many people find necessary. Perhaps someone else can come
along, take the code, and implement them.


=head2 EXPORT

None by default.

=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

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
