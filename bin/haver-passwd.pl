#!/usr/bin/perl
# Copyright (C) 2003 Dylan William Hardison
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA


use strict;
use warnings;
use YAML qw(LoadFile DumpFile);
use Digest::SHA1 qw(sha1_base64);

my $file = shift or die "usage: $0 file";
my $data = LoadFile($file);

print "Password: ";
my $pass = readline STDIN;
chomp $pass;

$data->{password} = sha1_base64($pass);


DumpFile($file, $data);


