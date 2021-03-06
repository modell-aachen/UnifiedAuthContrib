# See bottom of file for license and copyright information

=begin TML

---+ package Foswiki::Users::UnifiedUserMapping @isa Foswiki::UserMapping');

This is an alternative user mapping that can unify existing user mappings and,
in addition, provide mappings of its own. Similarly, it supports using several
existing group mappings and provides its own.

=cut

package Foswiki::Users::UnifiedUserMapping;

use strict;
use warnings;

use Foswiki::UserMapping ();
our @ISA = ('Foswiki::UserMapping');

use Assert;
use Error qw( :try );

use Foswiki::Func;
use Foswiki::ListIterator;
use Foswiki::Meta;
use Foswiki::UnifiedAuth;
use Foswiki::UnifiedAuth::Providers::BaseUser;
use Foswiki::Plugins::AppManagerPlugin;


=begin TML

---++ ClassMethod new ($session, $impl)

Constructs a new user mapping handler of this type, referring to $session
for any required Foswiki services.

=cut

sub new {
    my ($class, $session) = @_;

    my $this = $class->SUPER::new($session, 'unified_auth_mapper');
    $this->{uac} = Foswiki::UnifiedAuth->new();

    my $base = \%Foswiki::UnifiedAuth::Providers::BaseUser::CUIDs;
    $this->{base_cuids} = $base;

    return $this;
}



=begin TML

---++ ObjectMethod finish()
Break circular references.

=cut

# Note to developers; please undef *all* fields in the object explicitly,
# whether they are references or not. That way this method is "golden
# documentation" of the live fields in the object.
sub finish {
    my $this = shift;

    delete $this->{eachGroupMember};
    delete $this->{singleGroupMembers};

    $this->{passwords}->finish() if $this->{passwords};
    $this->SUPER::finish();
    Foswiki::UnifiedAuth::finish();
    #TODO: finish providers
}

=begin TML

---++ ObjectMethod supportsRegistration() -> $boolean

Return true if the UserMapper supports registration (ie can create new users)

Default is *false*

=cut

sub supportsRegistration {
    my $this = shift;

    my $providerId = $Foswiki::cfg{UnifiedAuth}{AddUsersToProvider};
    return 0 unless $providerId;

    my $provider = $this->{uac}->authProvider($this->{session}, $providerId);
    return 0 unless $provider;

    return $provider->supportsRegistration();
}

sub userMayRegisterUsers {
    my ($this, $user) = @_;
    my $mayRegisterUsers = $Foswiki::cfg{UnifiedAuth}{MayRegisterUsers};
    if(defined $mayRegisterUsers && $mayRegisterUsers ne '' && !Foswiki::Func::isAnAdmin()) {
        my $cuid = Foswiki::Func::getCanonicalUserID($user);
        my @list = split(/\s*,\s*/, $mayRegisterUsers =~ s/^\s*//r =~ s/\s*$//r);
        return $Foswiki::Plugins::SESSION->{users}->isInUserList($cuid, \@list);
    }
    return 1;
}

=begin TML

---++ ObjectMethod handlesUser ( $cUID, $login, $wikiname) -> $boolean

Called by the Foswiki::Users object to determine which loaded mapping
to use for a given user (must be fast).

The user can be identified by any of $cUID, $login or $wikiname. Any of
these parameters may be undef, and they should be tested in order; cUID
first, then login, then wikiname.

=cut

sub handlesUser {
    return 1;
}

=begin TML

---++ ObjectMethod login2cUID($login, $dontcheck) -> cUID

Convert a login name to the corresponding canonical user name. The
canonical name can be any string of 7-bit alphanumeric and underscore
characters, and must map 1:1 to the login name.
(undef on failure)

(if $dontcheck is true, return a cUID for a nonexistant user too.
This is used for registration)

Note: This method was previously (in TWiki 4.2.0) known as getCanonicalUserID.
The name was changed to avoid confusion with Foswiki::Users::getCanonicalUserID,
which has a more generic function. However to support older user mappers,
getCanonicalUserID will still be called if login2cUID is not defined.

=cut

sub login2cUID {
    my ( $this, $login, $dontcheck ) = @_;

    my $cCUID = $this->{uac}->getCUID($login, 0, 1);
    return $cCUID if defined $cCUID;

    return $this->{base_cuids}->{$login} if defined $this->{base_cuids}->{$login};

    return $login if $dontcheck;
    return undef;
}

=begin TML

---++ ObjectMethod getLoginName ($cUID) -> login

Converts an internal cUID to that user's login
(undef on failure)

=cut

sub getLoginName {
    my ( $this, $cUID ) = @_;
    ASSERT($cUID) if DEBUG;

    $cUID = $this->{uac}->getCUID($cUID, 0 , 1);
    if ($cUID) {
        return $this->{uac}->db->selectrow_array(
        "SELECT login_name FROM users WHERE cuid=?", {}, $cUID);
    }

    return undef;
}

sub isActive {
    my ( $this, $cUID ) = @_;
    ASSERT($cUID) if DEBUG;

    $cUID = $this->{uac}->getCUID($cUID, 0 , 1);
    if ($cUID) {
        my ($deactivated, $uac_disabled) = $this->{uac}->db->selectrow_array(
            "SELECT deactivated, uac_disabled FROM users WHERE cuid=?", {}, $cUID);
        return 1 unless $deactivated || $uac_disabled;
    }

    return 0;
}

=begin TML

---++ ObjectMethod loginOrGroup2cUID ($login) -> cUID

Converts a login or group name to a cUID.
(undef on failure)

Not official foswiki API, but very useful to check acls.

=cut

sub loginOrGroup2cUID {
    my ( $this, $login ) = @_;
    ASSERT($login) if DEBUG;

    return $this->{uac}->getCUID($login);
}

=begin TML

---++ ObjectMethod addUser ($login, $wikiname, $password, $emails) -> $cUID

Add a user to the persistent mapping that maps from usernames to wikinames
and vice-versa.

$login and $wikiname must be acceptable to $Foswiki::cfg{NameFilter}.
$login must *always* be specified. $wikiname may be undef, in which case
the user mapper should make one up.

This function must return a canonical user id that it uses to uniquely
identify the user. This can be the login name, or the wikiname if they
are all guaranteed unigue, or some other string consisting only of 7-bit
alphanumerics and underscores.

If you fail to create a new user (for eg your Mapper has read only access),
<pre>
    throw Error::Simple('Failed to add user: '.$error);
</pre>
where $error is a descriptive string.

Throws an Error::Simple if user adding is not supported (the default).

=cut

sub addUser {
    my ( $this, $login, $wikiname, $password, $emails ) = @_;

    return $this->addUserWithCuid($login, $wikiname, $password, $emails, undef)
}

sub addUserWithCuid {
    my ( $this, $login, $wikiname, $password, $emails, $cuid ) = @_;

    my $provider = $this->_getProviderToAddUser();
    unless ($this->userMayRegisterUsers()) {
        throw Error::Simple("User " . Foswiki::Func::getWikiName() . " is not allowed to register new users.");
    }

    return $provider->addUser($login, $wikiname, $password, $emails, undef, $cuid);
}

sub _getProviderToAddUser {
    my ($this) = @_;
    my $addTo = $Foswiki::cfg{UnifiedAuth}{AddUsersToProvider};
    unless($addTo) {
        throw Error::Simple('Failed to add user: adding users is not supported, please configure {UnifiedAuth}{AddUsersToProvider}');
    }

    my $provider = $this->{uac}->authProvider($this->{session}, $addTo);
    unless($provider) {
        throw Error::Simple('Failed to add user: could not get provider: '.$provider);
    }
    return $provider;
}


=begin TML

---++ ObjectMethod removeUser( $cUID ) -> $boolean

Delete the users entry from this mapper. Throws an Error::Simple if
user removal is not supported (the default).

=cut

sub removeUser {
    my ( $this, $cUID ) = @_;

    # to be implemented later
    return '';
}

=begin TML

---++ ObjectMethod getWikiName ($cUID) -> $wikiname

Map a canonical user name to a wikiname.

Returns the $cUID by default.

=cut

sub getWikiName {
    my ( $this, $cUID ) = @_;
    ASSERT($cUID) if DEBUG;

    my $login = _isCUID($cUID);
    if ($login) {
        return $this->{uac}->db->selectrow_array(
            "SELECT wiki_name FROM users WHERE cuid=?", {}, $login);
    }

    return $this->{uac}->db->selectrow_array(
        "SELECT wiki_name FROM users WHERE login_name=?", {}, $cUID);
}

=begin TML

---++ ObjectMethod userExists($cUID) -> $boolean

Determine if the user already exists or not. Whether a user exists
or not is determined by the password manager.

Subclasses *must* implement this method.

=cut

sub userExists {
    my ( $this, $cUID ) = @_;
    ASSERT($cUID) if DEBUG;

    # Do this to avoid a password manager lookup
    return 1 if $cUID eq $this->{session}->{user};

    my $loginName = $this->getLoginName($cUID);
    return 0 unless defined($loginName);

    return 1;
}

=begin TML

---++ ObjectMethod eachUser () -> $iterator

Get an iterator over the list of all cUIDs of the registered
users *not* including groups.

Subclasses *must* implement this method.

=cut

sub eachUser {
    my ($this) = @_;

    my $list = $this->{uac}->db->selectcol_arrayref(
        "SELECT cuid u FROM users"
    );
    return new Foswiki::ListIterator($list);
}

sub getDisplayName {
    my ($this, $login) = @_;

    my $cuid = _isCUID($login);
    if ($cuid) {
        return $this->{uac}->db->selectrow_array(
            "SELECT display_name FROM users WHERE cuid=? UNION SELECT name AS display_name FROM groups WHERE cuid=?", {}, $cuid, $cuid
        ) || $cuid;
    }

    return $this->{uac}->db->selectrow_array(
        "SELECT display_name FROM users WHERE login_name=?", {}, $login
    ) || $login;
}

sub getDisplayAttributesOfLogin {
    my ($this, $login, $data) = @_;

    # Note: BaseUserMapping_XXX is not a login name

    my $db = $this->{uac}->db;

    # get pid
    my $pid = $db->selectrow_array('SELECT name from providers LEFT OUTER JOIN users on (providers.pid = users.pid) WHERE login_name=? ', {}, $login);
    return 0 unless $pid;

    my $provider = $this->{uac}->authProvider($this->{session}, $pid);
    return 0 unless $provider;

    return $provider->getDisplayAttributesOfLogin($login,$data);
}

sub getUsers{
    my ($this, $opts) = @_;
    my ($fields, $basemapping) = (
        $opts->{fields},
        $opts->{basemapping}
    );

    my $db = $this->{uac}->db;

    my $cond = '';
    if($basemapping eq 'skip') {
        my $session = $Foswiki::Plugins::SESSION;
        $cond = "AND pid!='" . $this->{uac}->authProvider($session, '__baseuser')->getPid() . "'";
    } elsif ($basemapping eq 'adminonly') {
        my $session = $Foswiki::Plugins::SESSION;
        my $base = $this->{uac}->authProvider($session, '__baseuser');
        my $admin = $base->getAdminCuid();
        my $pid = $base->getPid();
        $cond = "AND pid !='$pid' OR cuid='$admin'";
    }
    my $statement = <<SQL;
SELECT $fields FROM users WHERE deactivated=0 $cond;
SQL
    return $db->selectall_arrayref($statement, undef);
}

=begin TML

---++ ObjectMethod findUserByEmail( $email ) -> \@users
   * =$email= - email address to look up
Return a list of canonical user names for the users that have this email
registered with the password manager or the user mapping manager.

=cut

sub findUserByEmail {
    my ( $this, $email ) = @_;
    ASSERT($email) if DEBUG;

    return $this->{uac}->db->selectcol_arrayref(
        "SELECT cuid FROM users WHERE email=?", {}, $email
    ) || [];
}

=begin TML

---++ ObjectMethod getEmails($name) -> @emailAddress

If $name is a cUID, return that user's email addresses. If it is a group,
return the addresses of everyone in the group.

Duplicates should be removed from the list.

=cut

sub getEmails {
    my ($this, $user, $seen) = @_;

    $seen ||= {};
    my %emails = ();
    if ($seen->{$user}) {
        #print STDERR "preventing infinit recursion in getEmails($user)\n";
    } else {
        $seen->{$user} = 1;

        if ($this->isGroup($user)) {
            my $it = $this->eachGroupMember($user);
            while ($it->hasNext()) {
                foreach ($this->getEmails($it->next(), $seen)) {
                    $emails{$_} = 1;
                }
            }
        } else {
            my @mails = $this->mapper_getEmails($user);
            foreach (@mails) {
                $emails{$_} = 1;
            }
        }
    }

    return keys %emails;
}


sub mapper_getEmails {
    my ($this, $user) = @_;

    my $uac = Foswiki::UnifiedAuth->new();
    my $cuid = $this->_userToCUID($user);

    my $addr;
    eval { # XXX
        $addr = $uac->db->selectrow_array(
            "SELECT email FROM users WHERE cuid=?", {}, $cuid
        );
    };
    if($@) {
        Foswiki::Func::writeWarning($@);
    }
    return () unless $addr;
    return split(';', $addr);
}

sub setEmails {
    my $this = shift;

    return $this->mapper_setEmails(@_);
}

sub mapper_setEmails {
    my $this = shift;
    my $cuid = shift;
    my $mails = join( ';', @_ );

    my $db = $this->{uac}->db();

    $cuid = $this->_userToCUID($cuid);
    my $providerName = $db->selectrow_array("SELECT providers.name FROM providers JOIN users USING (pid) WHERE users.cuid=?", {}, $cuid);
    my $provider = $this->{uac}->authProvider($this->{session}, $providerName);

    unless($provider->supportsEmailChange()) {
        my $error = Foswiki::Func::expandCommonVariables('%MAKETEXT{"Unfortunately the email can not be changed for your type of user."}%');
        throw Error::Simple($error);
    }

    return $db->do("UPDATE users SET email=? WHERE cuid=?", {}, $mails, $cuid);
}

=begin TML

---++ ObjectMethod findUserByWikiName ($wikiname) -> list of cUIDs associated with that wikiname
   * =$wikiname= - wikiname to look up
Return a list of canonical user names for the users that have this wikiname.
Since a single wikiname might be used by multiple login ids, we need a list.

Note that if $wikiname is the name of a group, the group will *not* be
expanded.

Subclasses *must* implement this method.

=cut

sub findUserByWikiName {
    my ( $this, $wn, $skipExistanceCheck ) = @_;

    # ToDo.
    my $cuid = _isCUID($wn);
    if ($cuid) {
        return $this->{uac}->db->selectrow_arrayref(
            "SELECT cuid FROM users WHERE cuid=?", {}, $cuid) || [];
    }

    # ToDo
    return [$wn] if $this->isGroup($wn);


    return $this->{uac}->db->selectrow_arrayref(
        'SELECT cuid FROM users WHERE login_name=? OR wiki_name=?', {}, $wn, $wn) || [];
}


=begin TML

---++ ObjectMethod checkPassword( $login, $passwordU ) -> $boolean

Finds if the password is valid for the given login. This is called using
a login name rather than a cUID because the user may not have been mapped
at the time it is called.

Returns 1 on success, undef on failure.

Default behaviour is to return 1.

=cut

sub checkPassword {
    my ( $this, $login, $password ) = @_;

    return $this->{uac}->checkPassword($this->{session}, $login, $password);
}

=begin TML

---++ ObjectMethod setPassword( $cUID, $newPassU, $oldPassU ) -> $boolean

If the $oldPassU matches matches the user's password, then it will
replace it with $newPassU.

If $oldPassU is not correct and not 1, will return 0.

If $oldPassU is 1, will force the change irrespective of
the existing password, adding the user if necessary.

Otherwise returns 1 on success, undef on failure.

Default behaviour is to fail.

=cut

sub setPassword {
    my ( $this, $login, $newUserPassword, $oldUserPassword ) = @_;

    return $this->{uac}->setPassword($this->{session}, $login, $newUserPassword, $oldUserPassword);
}

=begin TML

---++ ObjectMethod passwordError( ) -> $string

Returns a string indicating the error that happened in the password handlers
TODO: these delayed errors should be replaced with Exceptions.

returns undef if no error (the default)

=cut
sub passwordError {
    return;
}

=begin TML

---++ ObjectMethod eachGroupMember ($group, $expand) -> $iterator

Return a iterator over the canonical user ids of users that are members
of this group. Should only be called on groups.

Note that groups may be defined recursively, so a group may contain other
groups. Unless $expand is set to false, this method should *only* return
users i.e.  all contained groups should be fully expanded.

Subclasses *must* implement this method.

=cut

sub eachGroupMember {
    my ($this, $group, $options) = @_;
    my $expand = $options->{expand};
    $expand = 1 unless (defined $expand);
    # $expand = 0;

    if ( Scalar::Util::tainted($group) ) {
        $group = Foswiki::Sandbox::untaint( $group,
            \&Foswiki::Sandbox::validateTopicName );
    }

    my $cache = $expand ? 'eachGroupMember' : 'singleGroupMembers';

    if (defined($this->{$cache}->{$group})) {
        return new Foswiki::ListIterator($this->{$cache}->{$group});
    }

    my $db = $this->{uac}->db;
    my ($cuid, $name);
    if(_isCUID($group)) {
        $cuid = $group;
        $name = $db->selectrow_array(
            'SELECT name FROM groups WHERE cuid=?', {}, $group);
    } else {
        $name = $group;
        $cuid = $db->selectrow_array(
            'SELECT cuid FROM groups WHERE name=?', {}, $group);
    }
    return new Foswiki::ListIterator() unless $cuid && $name;

    my $entries;
    if($expand) {
        $entries = $this->_expandGroupRecursive($cuid);
    } else {
        $entries = $db->selectcol_arrayref(<<'SQL', {}, $cuid);
SELECT wiki_name FROM users
JOIN group_members
    ON (group_members.u_cuid=users.cuid AND group_members.g_cuid=$1)
UNION
    SELECT name FROM groups
        JOIN nested_groups
            ON (groups.cuid=nested_groups.child AND nested_groups.parent=$1)
ORDER BY wiki_name
SQL
    }

    $this->{$cache}->{$name} = $entries;
    $this->{$cache}->{$cuid} = $entries;
    return new Foswiki::ListIterator($this->{$cache}->{$cuid});
}

=begin TML

---++ ObjectMethod isAdmin( $cUID ) -> $boolean

True if the user is an administrator.

=cut

sub isAdmin {
    my ($this, $cuid) = @_;
    return 0 unless defined $cuid;
    return (Foswiki::UnifiedAuth::Providers::BaseUser::isAdminUser($cuid) || $this->isInGroup($cuid, $Foswiki::cfg{SuperAdminGroup}));
}

=begin TML

---++ ObjectMethod isGroup ($name) -> boolean

Establish if a user refers to a group or not. If $name is not
a group name it will probably be a canonical user id, though that
should not be assumed.

Subclasses *must* implement this method.

=cut

sub isGroup {
    my ( $this, $user ) = @_;

    return 0 unless defined $user;

    # ToDo
    return 1 if ($user eq $Foswiki::cfg{SuperAdminGroup} || $user eq 'NobodyGroup' || $user eq 'BaseGroup');

    return 1 if $this->{uac}->getCUID($user, 1);

    return 0;
}

=begin TML

---++ ObjectMethod eachGroup () -> $iterator

Get an iterator over the list of all the group names.

Subclasses *must* implement this method.

=cut

sub eachGroup {
    my ($this) = @_;

    my $list = $this->{uac}->db->selectcol_arrayref(
        "SELECT name FROM groups ORDER BY name ASC"
    );
    return new Foswiki::ListIterator($list);
}

=begin TML

---++ ObjectMethod eachMembership($cUID) -> $iterator

Return an iterator over the names of groups that $cUID is a member of.

Subclasses *must* implement this method.

=cut

sub eachMembership {
    my ($this, $user) = @_;

    return new Foswiki::ListIterator($this->getMemberships($user));
}

=begin TML

---++ ObjectMethod getMemebershipsCUID($user) -> \@groups

Return a list of the cUIDs, of which the user is a member of.

Not official foswiki API, but useful for checking acls.

=cut

sub getMembershipsCUID {
    my ($this, $user) = @_;
    my $cuid = $this->_userToCUID($user);

    my $sql = <<'SQL';
WITH RECURSIVE r(parent) AS (
    SELECT g_cuid as parent
        FROM group_members
        WHERE u_cuid=$1
    UNION
    SELECT n.parent as parent
        FROM r
        INNER JOIN nested_groups n
        ON r.parent=n.child
)
SELECT * FROM r
SQL

    return $this->{uac}->db->selectcol_arrayref($sql, {}, $cuid);
}

sub getMemberships {
    my ($this, $user) = @_;
    my $cuid = $this->_userToCUID($user);

    my $sql = <<'SQL';
SELECT groups.name FROM
(
    WITH RECURSIVE r(parent) AS (
        SELECT g_cuid as parent
            FROM group_members
            WHERE u_cuid=$1
        UNION
        SELECT n.parent as parent
        FROM r
        INNER JOIN nested_groups n
        ON r.parent=n.child
    )
    SELECT * FROM r
) asCuids
JOIN groups ON (groups.cuid=asCuids.parent)
SQL

    return $this->{uac}->db->selectcol_arrayref($sql, {}, $cuid);
}

=begin TML

---++ ObjectMethod groupAllowsView($group) -> boolean

returns 1 if the group is able to be viewed by the current logged in user

=cut

sub groupAllowsView {
    my ($this, $group) = @_;
    my $user = $this->{session}->{user};
    return 1 if $this->{session}->{users}->isAdmin($user);

    $group = Foswiki::Sandbox::untaint($group,
        \&Foswiki::Sandbox::validateTopicName);
    my ($grpWeb, $grpName) = Foswiki::Func::normalizeWebTopicName(
        $Foswiki::cfg{UsersWebName}, $group);

    # If a Group or User topic normalized somewhere else,
    # doesn't make sense, so ignore the Webname
    $grpWeb = $Foswiki::cfg{UsersWebName};
    $grpName = undef if (not $this->{session}->topicExists($grpWeb, $grpName));
    my $cuid = $this->_userToCUID($user);
    return Foswiki::Func::checkAccessPermission(
        'VIEW', $cuid, undef, $grpName, $grpWeb);
}

=begin TML

---++ ObjectMethod groupAllowsChange($group) -> boolean

returns 1 if the group is able to be modified by the current logged in user

=cut

sub groupAllowsChange {
    my ($this, $group, $user) = @_;
    ASSERT(defined $user) if DEBUG;

    my $cuid = $this->_userToCUID($user);
    $group = Foswiki::Sandbox::untaint($group,
        \&Foswiki::Sandbox::validateTopicName);
    my ($grpWeb, $grpName) = Foswiki::Func::normalizeWebTopicName(
        $Foswiki::cfg{UsersWebName}, $group);

    # SMELL: Should NobodyGroup be configurable?
    return 0 if $grpName eq 'NobodyGroup';
    return 1 if $this->{session}->{users}->isAdmin($user);

    # If a Group or User topic normalized somewhere else,
    # doesn't make sense, so ignore the Webname
    $grpWeb = $Foswiki::cfg{UsersWebName};

    $grpName = undef if (not $this->{session}->topicExists($grpWeb, $grpName));
    return Foswiki::Func::checkAccessPermission(
        'CHANGE', $cuid, undef, $grpName, $grpWeb);
}

=begin TML

---++ ObjectMethod addToGroup( $cuid, $group, $create ) -> $boolean
adds the user specified by the cuid to the group.

Mapper should throws Error::Simple if errors are encountered.  For example,
if the group does not exist, and the create flag is not supplied:
<pre>
    throw Error::Simple( $this->{session}
        ->i18n->maketext('Group does not exist and create not permitted')
    ) unless ($create);
</pre>

=cut

sub addUserToGroup {
    my ($this, $cuid, $group, $create) = @_;

    $group = Foswiki::Sandbox::untaint($group, \&Foswiki::Sandbox::validateTopicName);
    my ($grpWeb, $grpName) = Foswiki::Func::normalizeWebTopicName(
        $Foswiki::cfg{UsersWebName}, $group);
    $grpWeb = $Foswiki::cfg{UsersWebName};

    unless ($grpName =~ m/Group$/) {
        throw Error::Simple(
            $this->{session}->i18n->maketext('Group names must end in Group')
        );
    }

    if ($grpName eq 'NobodyGroup' || $grpName eq 'BaseGroup') {
        throw Error::Simple(
            $this->{session}->i18n->maketext(
                'Users cannot be added to [_1]', $grpName)
        );
    }

    if (!$create && !Foswiki::Func::topicExists($grpWeb, $grpName)) {
        throw Error::Simple(
            $this->{session}->i18n->maketext(
                'Users cannot be added to [_1]', $grpName)
        );
    }
    my $actor = $this->_userToCUID($this->{session}->{user});
    my $actor_wikiname = $this->getWikiName($actor);
    my $isGroup = $this->isGroup($grpName);

    if ($isGroup && !$this->groupAllowsChange($grpName, $actor)) {
        throw Error::Simple(
            $this->{session}->i18n->maketext(
                'CHANGE not permitted by [_1]', $actor_wikiname)
        );
    }

    my $db = $this->{uac}->db;
    if (!$isGroup && !$create) {
        throw Error::Simple(
            $this->{session}->i18n->maketext(
                'Group does not exist and create not permitted')
        );
    }
    my $grpCuid = $this->{uac}->getOrCreateGroup($grpName, $this->getPid());

    if ($cuid) {
        my $isNested = $this->isGroup($cuid);
        my $statement;

        if ($isNested) {
            $cuid = $this->{uac}->getCUID($cuid, 1, 0);
            $statement = 'INSERT INTO nested_groups (parent, child) VALUES(?, ?)';
        } else {
            $cuid = $this->_userToCUID($cuid);
            $statement = 'INSERT INTO group_members (g_cuid, u_cuid) VALUES(?, ?)';
        }

        $db->begin_work;
        $db->do($statement, {}, $grpCuid, $cuid);
        $db->commit;
    }

    $this->_writeGroupTopic($grpWeb, $grpName, $actor, $grpCuid);
    $this->_clearGroupCache($grpName);

    return 1;
}

sub getPid {
    return shift->{uac}->getPid('__uauth')
}

=begin TML

---++ ObjectMethod removeFromGroup( $cuid, $group ) -> $boolean

Mapper should throws Error::Simple if errors are encountered.  For example,
if the user does not exist in the group:
<pre>
   throw Error::Simple(
      $this->{session}->i18n->maketext(
         'User [_1] not in group, cannot be removed', $cuid
      )
   );
</pre>

=cut

sub removeUserFromGroup {
    my ($this, $cuid, $grpName) = @_;

    $grpName = Foswiki::Sandbox::untaint($grpName,
        \&Foswiki::Sandbox::validateTopicName);
    my ($grpWeb, $groupTopic) = Foswiki::Func::normalizeWebTopicName(
        $Foswiki::cfg{UsersWebName}, $grpName);
    $grpWeb = $Foswiki::cfg{UsersWebName};

    throw Error::Simple(
        $this->{session}->i18n->maketext(
            'Users cannot be removed from [_1]', $grpName)
    ) if ( $grpName eq 'BaseGroup' );

    throw Error::Simple(
        $this->{session}->i18n->maketext(
            '[_1] cannot be removed from [_2]',
            (
                $Foswiki::cfg{AdminUserWikiName}, $Foswiki::cfg{SuperAdminGroup}
            )
        )
    ) if ($grpName eq "$Foswiki::cfg{SuperAdminGroup}" && $cuid eq 'BaseUserMapping_333');

    if (!Foswiki::Func::topicExists($grpWeb, $grpName)) {
        throw Error::Simple(
            $this->{session}->i18n->maketext(
                'Users cannot be added to [_1]', $grpName)
        );
    }
    if ($this->isGroup($grpName)) {
        my $db = $this->{uac}->db;
        my $grp = $db->selectrow_hashref(
            'SELECT cuid, name FROM groups WHERE name=?', {}, $grpName);
        my $isNested = $this->isGroup($cuid);

        my $statement;
        if ($isNested) {
            $cuid = $this->{uac}->getCUID($cuid, 1, 0);
            $statement = 'DELETE FROM nested_groups WHERE parent=? AND child=?';
        } else {
            $cuid = $this->_userToCUID($cuid);
            $statement = 'DELETE FROM group_members WHERE g_cuid=? AND u_cuid=?';
        }

        $db->begin_work;
        $db->do($statement, {}, $grp->{cuid}, $cuid);
        $db->commit;

        my $actor = $this->_userToCUID($this->{session}->{user});
        $this->_writeGroupTopic($grpWeb, $grpName, $actor, $grp->{cuid});
        $this->_clearGroupCache($grpName);
        return 1;
    }

    return 0;
}

sub isInGroup {
    my ( $this, $user, $group, $options ) = @_;

    return 0 unless $group;

    if($group eq $Foswiki::cfg{SuperAdminGroup}) {
        return 1 if Foswiki::UnifiedAuth::Providers::BaseUser::isAdminUser($user);
        # other members will be detected below
    }

    $user = $this->{base_cuids}->{$user} if defined $this->{base_cuids}->{$user};

    # TODO: BaseGroup

    # NobodyGroup will simply return no g_cUID

    my $u_cUID = $this->{uac}->getCUID($user, 0, 1);
    my $g_cUID = $this->{uac}->getCUID($group, 1, 0);
    return 0 unless defined $u_cUID && defined $g_cUID;

    return $this->_isInGroupCuid($u_cUID, $g_cUID, {});
}

# Like isInGroup but expects to be called with valid cuids.
sub _isInGroupCuid {
    my ( $this, $u_cUID, $g_cUID, $seen ) = @_;

    my $db = $this->{uac}->db;

    # look in group itself
    return 1 if $db->selectrow_array('SELECT count(u_cuid) FROM group_members WHERE g_cuid=? AND u_cuid=?',
        {}, $g_cUID, $u_cUID);

    # do we have nesting?
    my $nested = $db->selectcol_arrayref('SELECT child FROM nested_groups WHERE parent=?',
        {}, $g_cUID);
    if($nested) {
        # do not recurse in infinite loops
        $seen->{$g_cUID} = 1;

        foreach my $nCuid ( @$nested ) {
            next if $seen->{$nCuid};
            return 1 if $this->_isInGroupCuid($u_cUID, $nCuid, $seen);
        }
    }

    return 0;
}

sub _writeGroupTopic {
    my ($this, $web, $topic, $author, $cuid) = @_;

    my @members;
    my $db = $this->{uac}->db;
    my @users = map {$_->{wiki_name}} @{$db->selectall_arrayref(<<SQL, {Slice => {}}, $cuid)};
SELECT u.wiki_name FROM users AS u
JOIN group_members AS g ON u.cuid=g.u_cuid
WHERE g.g_cuid=?
SQL

    my @groups = map {$_->{name}} @{$db->selectall_arrayref(<<SQL, {Slice => {}}, $cuid)};
SELECT g.name FROM groups AS g
JOIN nested_groups AS n ON g.cuid=n.child
WHERE n.parent=?
SQL

    push @members, @users, @groups;

    my $meta = Foswiki::Meta->load($this->{session}, $web, $topic);

    my @acl;
    my @canChange = ();

    my $keyUserAdministratedPref = $meta->get('PREFERENCE', 'KEYUSER_ADMINISTRATED');
    if( !(defined $keyUserAdministratedPref) && $topic ne 'AdminGroup' && $topic ne 'NobodyGroup' ) {
        $meta->putKeyed('PREFERENCE', {
            type  => 'Set',
            name  => 'KEYUSER_ADMINISTRATED',
            title => 'KEYUSER_ADMINISTRATED',
            value => '1'
        });
    }

    $keyUserAdministratedPref = $meta->get('PREFERENCE', 'KEYUSER_ADMINISTRATED');

    if( $keyUserAdministratedPref && $keyUserAdministratedPref->{'value'}) {
        push @canChange, 'KeyUserGroup';
        push @canChange, 'GlobalKeyUserGroup' if Foswiki::Plugins::AppManagerPlugin::isMultisiteEnabled();
    } else {
        push @canChange, $topic;
    }
    my $pref = $meta->get('PREFERENCE', 'ALLOWTOPICCHANGE');

    @acl = split(/,/, $pref->{value}) if defined $pref && $pref->{value};
    @acl = map {$_ =~ s/^\s+|\s+$//gr} @acl;

    foreach my $entry (@acl) {
        push @canChange, $entry unless grep {$_ eq $entry} @canChange;
    }

    $meta->putKeyed('PREFERENCE', {
        type  => 'Set',
        name  => 'GROUP',
        title => 'GROUP',
        value => join(', ', @members)
    });
    $meta->putKeyed( 'PREFERENCE', {
        type  => 'Set',
        name  => 'ALLOWTOPICCHANGE',
        title => 'ALLOWTOPICCHANGE',
        value => join(',', @canChange)
    });
    $meta->putKeyed('PREFERENCE', {
        type  => 'Set',
        name  => 'VIEW_TEMPLATE',
        title => 'VIEW_TEMPLATE',
        value => 'GroupView'
    });

    $meta->saveAs($web, $topic, author => $author,
        forcenewrevision => ($topic eq $Foswiki::cfg{SuperAdminGroup}) || 0
    );
}

sub _clearGroupCache {
    my ($this, $grpName) = @_;

    delete $this->{eachGroupMember}->{$grpName};
    delete $this->{singleGroupMembers}->{$grpName};

    #SMELL:  This should probably be recursive.
    foreach my $groupKey ( keys( %{ $this->{singleGroupMembers} } ) ) {
        if ( $this->{singleGroupMembers}->{$groupKey} =~ m/$grpName/ ) {
            #           print STDERR "Deleting cache for $groupKey \n";
            delete $this->{eachGroupMember}->{$groupKey};
            delete $this->{singleGroupMembers}->{$groupKey};
        }
    }
}

sub _expandGroupRecursive {
    my ($this, $cuid) = @_;

    my $sql = <<'SQL';
SELECT
    users.wiki_name
FROM
    (SELECT u_cuid, g_cuid
        FROM group_members m
        INNER JOIN
            (WITH RECURSIVE r(parent, child) AS (
                SELECT parent, child
                    FROM nested_groups
                    WHERE parent=$1
                UNION
                SELECT n.parent as parent, n.child as child
                FROM r
                LEFT OUTER JOIN nested_groups n
                ON r.child=n.parent
                WHERE r.parent IS NOT NULL)
            SELECT * FROM r) c
        ON (c.child = m.g_cuid)
    UNION
    SELECT u_cuid, g_cuid
        FROM group_members
        WHERE g_cuid=$1) gm
    JOIN users ON (gm.u_cuid = users.cuid AND users.deactivated=0 AND users.uac_disabled=0)
    ORDER BY users.wiki_name
SQL

    my $db = $this->{uac}->db;
    return $db->selectcol_arrayref($sql, {}, $cuid);
}

# ToDo.
sub _isCUID {
    my $login = shift;

    return 0 unless defined $login;

    my $base = Foswiki::UnifiedAuth::Providers::BaseUser::getBaseUserCUID($login);
    return $base if defined $base;

    $login =~ s/_2d/-/g;
    return $login if Foswiki::UnifiedAuth::isCUID($login);

    0;
}

sub _userToCUID {
    my ($this, $user) = @_;
    return $this->{base_cuids}->{$user} if defined $this->{base_cuids}->{$user};

    return $this->{uac}->getCUID($user, 0, 1);
}

1;
__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2008-2010 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

Additional copyrights apply to some or all of the code in this
file as follows:

Copyright (C) 2016 Modell Aachen GmbH

Copyright (C) 2007-2008 Sven Dowideit, SvenDowideit@fosiki.com
and TWiki Contributors. All Rights Reserved.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
