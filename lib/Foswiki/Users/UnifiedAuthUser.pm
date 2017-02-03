# See bottom of file for license and copyright information

=begin TML

---+ package Foswiki::Users::UnifiedAuthUser

Unified password manager that can draw from multiple sources.

=cut

package Foswiki::Users::UnifiedAuthUser;
use strict;
use warnings;

use Crypt::PBKDF2;

use Foswiki::Users::HtPasswdUser;
use Foswiki::Users::Password ();
our @ISA = ('Foswiki::Users::Password');

use Assert;
use Error qw( :try );
use Fcntl qw( :DEFAULT :flock );

sub new {
    my ( $class, $session ) = @_;
    my $this = bless( $class->SUPER::new($session), $class );
    $this->{error} = undef;

    return $this;
}

# Note to developers; please undef *all* fields in the object explicitly,
# whether they are references or not. That way this method is "golden
# documentation" of the live fields in the object.
sub finish {
    my $this = shift;
    $this->SUPER::finish();
}

sub readOnly {
    return 0;
}

sub canFetchUsers {
    # TODO make dynamic
    return 0;
}

sub fetchPass {
    my ( $this, $login ) = @_;
    my $ret = 0;
    my $enc = '';
    my $userinfo;

    if( $login ) {
        my $uauth = Foswiki::UnifiedAuth->new();
        my $db = $uauth->db;
        $db = $uauth->db;

        my $userinfo = $db->selectrow_hashref("SELECT cuid, wiki_name, password FROM users WHERE users.login_name=?", {}, $login);
        if( $userinfo ) {
            $ret = $userinfo->{password};
        } else {
            $this->{error} = "Login $login invalid";
            $ret = undef;
        }
    } else {
        $this->{error} = 'No user';
    }
    return (wantarray) ? ( $ret, $userinfo ) : $ret;
}

sub _generatePwHash {
    my $password = shift;

    my $pbkdf2 = Crypt::PBKDF2->new(
        hash_class => 'HMACSHA2',
        hash_args => {
            sha_size => 512,
        },
        iterations => 10000,
        salt_len => 10,
    );
    return $pbkdf2->generate($password);
}

sub setPassword {
    my ( $this, $login, $newUserPassword, $oldUserPassword ) = @_;

    if ( defined($oldUserPassword) ) {
        unless ( $oldUserPassword eq '1' ) {
            return undef unless $this->checkPassword( $login, $oldUserPassword );
        }
    }
    elsif ( $this->fetchPass($login) ) {
        $this->{error} = $login . ' already exists';
        return 0;
    }

    my $uauth = Foswiki::UnifiedAuth->new();
    # XXX UTF-8
    my $pwHash;
    if ($newUserPassword) {
        $pwHash = _generatePwHash($newUserPassword);
    }
    my $db = $uauth->db;
    my $userinfo = $db->selectrow_hashref("SELECT cuid, email, display_name, deactivated FROM users WHERE users.login_name=?", {}, $login);
    my $cuid = $uauth->update_user('UTF-8', $userinfo->{cuid}, $userinfo->{email}, $userinfo->{display_name}, $userinfo->{deactivated}, $pwHash);
    my $cgis = $this->{session}->getCGISession();
    $cgis->param('force_set_pw', 0);

    $this->{error} = undef;
    return 1;
}

sub removeUser {
    my ( $this, $login ) = @_;
    # TODO
    $this->{error} = "Cannot remove users in this implementation";
    return;
}

sub checkPassword {
    my ( $this, $login, $password ) = @_;

    my $uauth = Foswiki::UnifiedAuth->new();
    my $db = $uauth->db;

    my $userinfo = $db->selectrow_hashref("SELECT cuid, wiki_name, password FROM users WHERE users.login_name=?", {}, $login);
    return undef unless $userinfo;
    if( $userinfo->{password} ) {
        my $pbkdf2 = Crypt::PBKDF2->new;
        return undef unless $pbkdf2->validate( $userinfo->{password}, $password );
    } else {
        my $topicPwManager = Foswiki::Users::HtPasswdUser->new($this->{session});
        return undef unless $topicPwManager->checkPassword( $userinfo->{wiki_name}, $password );
        my $cgis = $this->{session}->getCGISession();
        $cgis->param('force_set_pw', 1);
    }

    return $userinfo->{cuid};
}

sub isManagingEmails {
    return 0;
}

1;
__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2008-2010 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

Additional copyrights apply to some or all of the code in this
file as follows:

Copyright (C) 1999-2007 Peter Thoeny, peter@thoeny.org
and TWiki Contributors. All Rights Reserved. TWiki Contributors
are listed in the AUTHORS file in the root of this distribution.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.

