# See bottom of file for license and copyright information
use strict;
use warnings;

package UnifiedAuthContribTests;

use FoswikiFnTestCase;
our @ISA = qw( FoswikiFnTestCase );

use strict;
use warnings;

use Foswiki();
use Error qw ( :try );
use Foswiki::Contrib::UnifiedAuthContrib();
use Foswiki::UnifiedAuth::Providers::Ldap();

use Data::Dumper;
use Test::MockModule;

my $mocks; # mocks will be stored in a package variable, so we can unmock them reliably when the test finished

my $testPid = 123;

sub new {
    my ($class, @args) = @_;
    my $this = shift()->SUPER::new('UnifiedAuthContribTests', @args);
    return $this;
}

sub loadExtraConfig {
    my $this = shift;
    $this->SUPER::loadExtraConfig();
}

sub set_up {
    my $this = shift;

    $this->SUPER::set_up();

    $this->set_up_mocks();
}

sub set_up_mocks {
    my $this = shift;

    $mocks = {};
    foreach my $module (qw(
        Foswiki::UnifiedAuth
        Foswiki::UnifiedAuth::Providers::Ldap
    )) {
        $mocks->{$module} = Test::MockModule->new($module);
    }

    # standard mocks
    $mocks->{'Foswiki::UnifiedAuth::Providers::Ldap'}->mock('getPid', $testPid);
}

sub tear_down {
    my $this = shift;

    foreach my $module (keys %$mocks) {
        $mocks->{$module}->unmock_all();
    }

    $this->SUPER::tear_down();
}

# Test if...
# ... a no longer imported user gets removed from the db
# ... a still existing user does NOT get removed
sub test_ldapRefreshRemovesOldUsers {
    my ( $this ) = @_;

    my $session = $this->createNewFoswikiSession( $Foswiki::cfg{AdminUserLogin} || 'AdminUser' );
    my $ldap = Foswiki::UnifiedAuth::Providers::Ldap->new($session, 'test_ldap', {});
    $ldap->{userBase} = ['cn=Test'];

    my $db = $this->getMockDb(
        selectcol_arrayref => {
            'SELECT cuid from users where pid=? and uac_disabled=0' => { params => [{}, $testPid], result => ['11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'] },
        },
        do => {
            'UPDATE users SET uac_disabled=1 WHERE pid=? AND cuid=?' => { params => [{}, $testPid, '22222222-2222-2222-2222-222222222222'], result => [] },
        }
    );

    $mocks->{'Foswiki::UnifiedAuth::Providers::Ldap'}->mock('_refreshEachUsersCache', sub {
        my ($this, $base, $seenCuids) = @_;

        $seenCuids->{'11111111-1111-1111-1111-111111111111'} = 1;
        return 1;
    });

    $ldap->{uauth} = Foswiki::UnifiedAuth->new();

    $ldap->refreshUsersCache();
    $db->assertAllCalled();
}

# Test if...
# ... a no longer imported group gets removed from the db
# ... a still existing group does NOT get removed
sub test_ldapRefreshRemovesOldGroups {
    my ( $this ) = @_;

    my $session = $this->createNewFoswikiSession( $Foswiki::cfg{AdminUserLogin} || 'AdminUser' );
    my $ldap = Foswiki::UnifiedAuth::Providers::Ldap->new($session, 'test_ldap', {});
    $ldap->{groupBase} = ['dn=Test'];

    my $db = $this->getMockDb(
        selectcol_arrayref => {
            'SELECT name FROM groups WHERE pid=?' => { params => [{}, $testPid], result => ['groupA', 'groupB'] },
        },
        selectall_hashref => {
            'SELECT dn, cuid FROM users_ldap' => { params => ['dn', {}], result => { 'cn=groupA,dn=Test' => '33333333-3333-3333-3333-333333333333' } },
        },
    );

    $mocks->{'Foswiki::UnifiedAuth::Providers::Ldap'}->mock('_refreshEachGroupCache', sub {
        my ($this, $groupBase, $groupsCache, $groupsCacheDN) = @_;

        $groupsCache->{'groupA'} = 'cn=groupA';
        return 1;
    });

    $mocks->{'Foswiki::UnifiedAuth::Providers::Ldap'}->mock('_processGroups', '');

    $mocks->{'Foswiki::UnifiedAuth::Providers::Ldap'}->mock('_processVirtualGroups', '');

    my $groupRemoved;
    $mocks->{'Foswiki::UnifiedAuth'}->mock('removeGroup', sub {
        my ($uauth, %group) = @_;

        $this->assert($group{name} eq 'groupB', "Wrong group was removed: '$group{name}' instead of groupB");
        $groupRemoved = 1;

        return;
    });


    $ldap->{uauth} = Foswiki::UnifiedAuth->new();

    $ldap->refreshGroupsCache();
    $db->assertAllCalled();
    $this->assert($groupRemoved);
}

sub getMockDb {
    my $this = shift;
    my %queries = @_;

    $queries{testCase} = $this;

    my $db = bless \%queries, 'UnifiedAuthContribTestsDbMock';
    $mocks->{'Foswiki::UnifiedAuth'}->mock('db', $db);

    return $db;
}

package UnifiedAuthContribTestsDbMock;

use Data::Dumper;
use Data::Compare;

sub selectcol_arrayref {
    my $this = shift;
    unshift @_, 'selectcol_arrayref';
    return $this->pseudoDb(@_);
}

sub selectall_arrayref {
    my $this = shift;
    unshift @_, 'selectall_arrayref';
    return $this->pseudoDb(@_);
}

sub selectcol_hashref {
    my $this = shift;
    unshift @_, 'selectcol_hashref';
    return $this->pseudoDb(@_);
}

sub do {
    my $this = shift;
    unshift @_, 'do';
    return $this->pseudoDb(@_);
}

sub selectall_hashref {
    my $this = shift;
    unshift @_, 'selectall_hashref';
    return $this->pseudoDb(@_);
}

sub pseudoDb {
    my $this = shift;
    my $type = shift;
    my $query = shift;

    my $queries = $this->{$type};
    my $data = $queries->{$query};
    my $testCase = $this->{testCase};
    $testCase->assert($data, "Unexpected query: '$query' for type $type");
    $testCase->assert(Compare(\@_, $data->{params}), "db call '$query' for type $type expected with " . Dumper($data->{params}) . " but got " . Dumper(\@_));

    $data->{called}++;

    return $data->{result};
}

sub assertAllCalled {
    my $this = shift;

    my $testCase = $this->{testCase};
    foreach my $type ( qw(selectcol_arrayref selectall_arrayref selectcol_hashref) ) {
        next unless $this->{$type};
        foreach my $query ( keys %{$this->{$type}} ) {
            $testCase->assert($this->{$type}->{$query}, "Query '$query' for $type has not been called");
        }
    }
}

1;
__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Author: Modell Aachen GmbH

Copyright (C) 2008-2011 Foswiki Contributors. Foswiki Contributors
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

