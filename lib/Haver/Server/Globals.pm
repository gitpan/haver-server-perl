# Haver::Server::Globals - The Server class.
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
package Haver::Server::Globals;
use strict;
use open ":utf8";

our %Feature;
our $Store;
our $Config;
our $Roles;
our $Registry;
our $VERSION = 0.055;

BEGIN {
	use Exporter;
	use base 'Exporter';

	our $RELOAD  = 1;
	our @EXPORT = ();
	our @EXPORT_OK = qw( $Registry $Config %Feature $Store);
}

use Haver::Server::Registry;
use Haver::Config;


sub init {
	my ($class, %opts) = @_;

	return if $Config || $Store || $Registry;

	$Registry = $opts{Registry};
	$Config   = $opts{Config};
	$Store    = $opts{Store};
	%Feature  = $opts{Feature} ? %{ $opts{Feature} } : () ;
}


1;
__END__

=head1 NAME

Haver::Server::Globals - Export of global variables.

=head1 SYNOPSIS

  use Haver::Server::Globals qw( $Config $Registry %Features );

=head1 DESCRIPTION

Haver::Server::Globals exports a few variables
that are needed everywhere. These variables are:

$Config -- the data from the global config file.

$Registry -- the object registry, a database of users and
and channels,and hammers...

$Store -- global storage for bits and bobs.

%Features -- a hash for the lookup of what features are available.


=head2 EXPORT

None by default.

$Store, $Config, $Registry, %Features.


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
