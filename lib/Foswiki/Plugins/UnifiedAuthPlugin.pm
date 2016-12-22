# See bottom of file for license and copyright information

package Foswiki::Plugins::UnifiedAuthPlugin;

use strict;
use warnings;

use Foswiki::Func;
use Foswiki::Contrib::PostgreContrib;

our $VERSION = '1.0';
our $RELEASE = "1.0";
our $SHORTDESCRIPTION = 'Handlers for UnifiedAuthContrib';

our $connection;

sub initPlugin {
    Foswiki::Func::registerTagHandler(
        'AUTHPROVIDERS',
        \&_AUTHPROVIDERS
    );

    Foswiki::Func::registerTagHandler('TOTALUSERS', \&_TOTALUSERS);
    return 1;
}

sub _AUTHPROVIDERS {
    my ( $session, $attrs, $topic, $web ) = @_;
    # TODO
    return "AUTHPROVIDERS: not implemented yet";
}

sub _TOTALUSERS {
  my($session, $params, $topic, $web, $topicObject) = @_;
  my $db = _getConnection();
  $db->selectrow_array("SELECT COUNT(cuid) FROM users", {});
}

sub finishPlugin {
  $connection->finish if $connection;
}

sub _getConnection {
  return $connection if $connection && !$connection->{finished};
  $connection = Foswiki::Contrib::PostgreContrib::getConnection('foswiki_users');
  $connection->{db};
}

1;

__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2008-2013 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
