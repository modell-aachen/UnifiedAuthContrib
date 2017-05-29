# See bottom of file for license and copyright information

package Foswiki::Contrib::UnifiedAuthContrib;

use strict;
use warnings;

our $VERSION = '1.0';
our $RELEASE = "1.0";
our $SHORTDESCRIPTION = 'User management supporting multiple authentication and data sources';

our $SITEPREFS = {
    USER_CREATE_ALLOW_CHANGE_LOGINNAME => 0
};

sub maintenanceHandler {
    Foswiki::Plugins::MaintenancePlugin::registerCheck("unifiedauth:dbencoding", {
        name => "UnifiedAuth: DB encoding.",
        description => "Check if the database for UnifiedAuth useing the UTF8 encoding",
        check => sub {
            my $result = { result => 0 };
            my $ua = Foswiki::UnifiedAuth::new();
            my $db = $ua->db();
            my $sth=$db->prepare("SHOW SERVER_ENCODING");
            $sth->execute();
            my ($value) = $sth->fetchrow_array();
            $sth->finish();
            if ($value =~ /SQL_ASCII/) {
                $result->{result} = 1;
                $result->{priority} = $Foswiki::Plugins::MaintenancePlugin::CRITICAL;
                $result->{solution} = "Change the database encoding to UTF8";
            }
            return $result;
       }
    });
}

1;

__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2008-2015 Foswiki Contributors. Foswiki Contributors
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
