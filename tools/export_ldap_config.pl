#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

do '../bin/setlib.cfg';
require Foswiki;
Foswiki->new('admin');

$Data::Dumper::Terse = 1;
no warnings 'once';
my $result = Dumper($Foswiki::cfg{Ldap});
print $result;