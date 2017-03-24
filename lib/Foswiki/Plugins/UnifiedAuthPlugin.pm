# See bottom of file for license and copyright information

package Foswiki::Plugins::UnifiedAuthPlugin;

use strict;
use warnings;

use Foswiki::Func;
use Foswiki::Contrib::PostgreContrib;
use Foswiki::UnifiedAuth;

our $VERSION = '1.0';
our $RELEASE = "1.0";
our $SHORTDESCRIPTION = 'Handlers for UnifiedAuthContrib';

our $connection;

sub initPlugin {
    Foswiki::Func::registerTagHandler('AUTHPROVIDERS',\&_AUTHPROVIDERS);
    Foswiki::Func::registerTagHandler('TOTALUSERS', \&_TOTALUSERS);
    return 1;
}

sub _AUTHPROVIDERS {
    my ( $session, $attrs, $topic, $web ) = @_;

    my $providers = $Foswiki::cfg{UnifiedAuth}{Providers};
    return '' unless defined $providers;

    my $choose = 0;
    my $ctx = Foswiki::Func::getContext();
    my $auth = Foswiki::UnifiedAuth->new();

    while (my ($id, $hash) = each %$providers) {
      next unless $hash->{module} =~ /Google|Facebook|Steam/;
      my $provider = $auth->authProvider($session, $id);
      next unless $provider->enabled;
      $ctx->{'UA_'.uc($id)} = 1;
      $ctx->{'UA_CHOOSE'} = 1;
    }

    my $path = '%PUBURLPATH%/%SYSTEMWEB%/UnifiedAuthContrib';
    Foswiki::Func::addToZone(
      'head',
      'uauth:css',
      "<link rel=\"stylesheet\" type=\"text/css\" media=\"all\" href=\"$path/css/uauth.css?version=$RELEASE\" />"
    );

    if ($ctx->{'UA_CHOOSE'}) {
      Foswiki::Func::addToZone(
        'script',
        'uauth:js',
        "<script type=\"text/javascript\" src=\"$path/js/uauth.js?version=$RELEASE\"></script>",
        'JQUERYPLUGIN::FOSWIKI::PREFERENCES'
      );
    }

    return '';
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
