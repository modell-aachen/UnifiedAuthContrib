package Foswiki::UnifiedAuth::Provider;

use JSON;
use strict;
use warnings;

use Foswiki::UnifiedAuth;

use Digest::SHA qw(sha1_base64);
use Error qw( :try );
use Net::CIDR;

# Return values for 'initiateLogin'
our $INITIATE_LOGIN_CONTINUE = 0; # no login screen rendered, continue with other providers
our $INITIATE_LOGIN_FINISHED = 1; # success, nothing else required to render a login screen
our $INITIATE_LOGIN_RENDERDEFAULT = 2; # success, however, please do render the default login

sub new {
    my ($class, $session, $id, $config) = @_;
    my $name = $class;
    $name =~ s/^Foswiki::UnifiedAuth::Providers:://;

    return bless {
        name => $name,
        id => $id,
        config => $config,
        session => $session,
    }, $class;
}

# Signal if this provider allows changing the email address.
# For providers with external sources (ldap) this does not make sense.
sub supportsEmailChange {
    return 0;
}

# Called by UnifiedLoading::loadSession when the user logged out
sub handleLogout {
    my ($this, $session) = @_;
    return unless $session;

    my $cgis = $session->getCGISession();
    $cgis->param("uauth_$this->{id}_logged_out", 1);
}

# Add user to provider.
# Return cuid if successful, perl-false otherwise.
sub addUser {
    return undef;
}

# Return perl-false if this provider can not be forced.
# Return (icon-html, text-TML) array for force button otherwise.
sub forceButton {
    return undef;
}

# Generates a secret, that a provider can use as a nonce.
# In contrast to the state, this secret will differ for every request.
# The state will be stored in the session and can be retrieved with
# validateSecret.
sub generateSecret {
    my ($this, $prefix, $state) = @_;

    my $cgis = $this->{session}->getCGISession();
    my $secret = $prefix . "_" . sha1_base64(rand() . $state);
    $secret =~ tr#+/=#-_~#;

    my $encodedState = $state =~ s#[=,]#'='.ord($1).'='#ger; # If this is a state as provided by _requestToState, this does nothing. However we can not be sure whats being passed in here.

    my $cgiKey = "uauth_$this->{id}_secret";
    my $storedSecrets = $cgis->param($cgiKey) || '';
    $cgis->param($cgiKey, "$storedSecrets,$secret=$encodedState");
    return $secret;
}

# Returns the associated state, if the secret is valid and also invalidates
# the secret.
# Returns undef, if the secret is invalid.
sub validateSecret {
    my ($this, $secret) = @_;

    return 0 unless $secret;

    my $cgis = $this->{session}->getCGISession();
    my $cgiKey = "uauth_$this->{id}_secret";
    my $storedSecrets = $cgis->param($cgiKey);
    return undef unless $storedSecrets;
    return undef unless $storedSecrets =~ s#(?:^|,)\Q$secret\E=([^,]*)(,|$)#$2#;
    my $encodedSecret = $1;

    # Invalidate the nonce, to we can no longer use it in replays.
    $cgis->param($cgiKey, $storedSecrets);

    return $encodedSecret =~ s#=(\d+)=#chr($1)#ger;
}

sub useDefaultLogin {
    return 0;
}

sub initiateLogin {
    my ($this, $state, $forced) = @_;

    if($forced) {
        my $cgis = $this->{session}->getCGISession;
        $cgis->clear("uauth_$this->{id}_logged_out");
        return $Foswiki::UnifiedAuth::Provider::INITIATE_LOGIN_RENDERDEFAULT;
    }

    return $Foswiki::UnifiedAuth::Provider::INITIATE_LOGIN_CONTINUE;
}

sub indexUser {
    my ($this, $cuid) = @_;
    return $this->refresh($cuid);
}

sub indexGroup {
    my ($this, $cuid) = @_;
    return $this->refresh($cuid);
}

sub refresh {
    my ($this, $cuid) = @_;

    return 1 unless $Foswiki::cfg{Plugins}{SolrPlugin}{Enabled};

    require Foswiki::Plugins::SolrPlugin;
    my $indexer = Foswiki::Plugins::SolrPlugin::getIndexer();

    my $uauth = Foswiki::UnifiedAuth->new();
    my $db = $uauth->db;

    $this->_indexUsers($db, $indexer, $cuid);
    $this->_indexGroups($db, $indexer, $cuid);
    0;
}

sub _indexUsers {
    my ($this, $db, $indexer, $cuid) = @_;

    my $provider = $Foswiki::cfg{UnifiedAuth}{Providers}{$this->{id}};
    my $pid = $this->getPid();

    my $userQuery = 'SELECT * FROM users WHERE pid=?';
    if($cuid) {
        my $quoted = $db->quote($cuid);
        $userQuery .= " AND cuid=$quoted";
        $indexer->deleteByQuery("type:\"ua_user\" cuid_s:\"$cuid\"");
    } else {
        $indexer->deleteByQuery("type:\"ua_user\" providerid_i:\"$pid\"");
    }

    my $users = $db->selectall_arrayref($userQuery, {Slice => {}}, $pid);
    foreach my $user (@$users) {
        my $groups = $db->selectall_arrayref(<<SQL, {Slice => {}}, $user->{cuid});
SELECT
  group_members.g_cuid,
  providers.name AS provider_name,
  groups.name AS group_name
FROM group_members
INNER JOIN groups ON (group_members.g_cuid=groups.cuid)
INNER JOIN providers ON (groups.pid=providers.pid)
WHERE u_cuid=?
SQL
        my @groupIds = map { $_->{g_cuid} } @$groups;
        my @groupNames = map { $_->{group_name} } @$groups;
        my @groupProviders = map { $_->{provider_name} } @$groups;

        my $userdoc = $indexer->newDocument();
        $userdoc->add_fields(
          'id' => $user->{cuid},
          'type' => 'ua_user',
          'web' => $Foswiki::cfg{UsersWebName},
          'cuid_s' => $user->{cuid},
          'loginname_s' => $user->{login_name},
          'wikiname_s' => $user->{wiki_name},
          'displayname_s' => $user->{display_name},
          'email_s' => $user->{email} || '',
          'mainprovidername_s' => $this->{id},
          'mainproviderdescription_s' => $provider->{description} || $this->{id},
          'mainprovidermodule_s' => $provider->{module},
          'providers_lst' => [$provider->{description} || $this->{id}],
          'providerid_i' => $pid,
          'deactivated_i' => $user->{deactivated},
          'groupids_lst' => \@groupIds,
          'groupnames_lst' => \@groupNames,
          'groupproviders_lst' => \@groupProviders,
          'url' => ''
        );

        try {
            $indexer->add($userdoc);
        } catch Error::Simple with {
            my $e = shift;
            $indexer->log("ERROR: $e->{-text}");
        };
    }
};

sub _indexGroups {
    my ($this, $db, $indexer, $cuid) = @_;

    my $provider = $Foswiki::cfg{UnifiedAuth}{Providers}{$this->{id}};
    my $pid = $this->getPid();

    my $groupQuery = 'SELECT * FROM groups WHERE pid=?';
    if($cuid) {
        my $quoted = $db->quote($cuid);
        $groupQuery .= " AND cuid=$quoted";
        $indexer->deleteByQuery("type:\"ua_group\" cuid_s:\"$cuid\"");
    } else {
        $indexer->deleteByQuery("type:\"ua_group\" providerid_i:\"$pid\"");
    }

    my $groups = $db->selectall_arrayref($groupQuery, {Slice => {}}, $pid);
    foreach my $group (@$groups) {
        my $members = $db->selectall_arrayref(<<SQL, {Slice => {}}, $group->{cuid});
SELECT
    string_agg(gm.g_cuid::character varying, ', ') as g_cuids,string_agg(g.name, ', ') as group_names, string_agg(p.name, ', ') as g_provider_name, u.cuid, u.login_name, u.wiki_name, u.display_name
FROM
    (SELECT u_cuid, g_cuid
        FROM group_members m
        INNER JOIN
            (WITH RECURSIVE r(parent, child) AS (
                SELECT parent, child
                    FROM nested_groups
                    WHERE parent=\$1
                UNION
                SELECT n.parent as parent, n.child as child
                FROM r
                LEFT OUTER JOIN nested_groups n
                ON r.child=n.parent
                WHERE r.parent IS NOT NULL)
            SELECT * FROM r) c
        ON (c.child = m.g_cuid)
    union
    SELECT u_cuid, g_cuid
        FROM group_members
        WHERE g_cuid=\$1) gm
JOIN users u
ON gm.u_cuid=u.cuid
JOIN groups g
ON g.cuid=gm.g_cuid
JOIN providers p
ON p.pid=g.pid
WHERE u.deactivated=0 AND u.uac_disabled=0
GROUP BY u.cuid;
SQL

        my (@memberIDs, @memberDNs, @memberWNs, @memberLNs);
        foreach my $m (@$members) {
            push @memberIDs, $m->{cuid};
            push @memberDNs, $m->{display_name};
            push @memberLNs, $m->{login_name};
            push @memberWNs, $m->{wiki_name};
        }

        my $active = $db->selectrow_array(<<SQL, {}, $group->{cuid});
SELECT COUNT(u.cuid)
FROM group_members m
JOIN users u ON m.u_cuid=u.cuid
WHERE u.deactivated=0 AND m.g_cuid=?;
SQL
        my $canChange = ($group->{name} =~ m/Group$/ && Foswiki::Func::topicExists($Foswiki::cfg{UsersWebName}, $group->{name}));
        my $grpdoc = $indexer->newDocument();
        $grpdoc->add_fields(
          'id' => $group->{cuid},
          'type' => 'ua_group',
          'web' => $Foswiki::cfg{UsersWebName},
          'cuid_s' => $group->{cuid},
          'groupname_s' => $group->{name},
          'mainprovidername_s' => $this->{id},
          'mainproviderdescription_s' => $provider->{description} || $this->{id},
          'providers_lst' => [$provider->{description} || $this->{id}],
          'providerid_i' => $pid,
          'activemembers_i' => $active,
          'memberids_lst' => \@memberIDs,
          'memberdisplaynames_lst' => \@memberDNs,
          'memberwikinames_lst' => \@memberWNs,
          'memberloginnames_lst' => \@memberLNs,
          'members_json' => to_json($members),
          'canChange_s' => $canChange,
          'url' => ''
        );

        try {
            $indexer->add($grpdoc);
        } catch Error::Simple with {
            my $e = shift;
            $indexer->log("ERROR: $e->{-text}");
        };
    }
};

sub enabled {
    my $this = shift;
    my $cfg = $this->{config};
    return 0 if defined $cfg->{enabled} && !$cfg->{enabled};

    return 1 unless $cfg->{deny} || $cfg->{allow};
    my $req = $this->{session}{request};
    my $addr = $req->remote_addr;

    if ($cfg->{deny}) {
        my @deny;
        foreach my $ip (split(/[\s,]+/, $cfg->{deny})) {
            push @deny, Net::CIDR::range2cidr($ip);
        }

        return 0 if Net::CIDR::cidrlookup($addr, @deny);
    }

    return 1 unless $cfg->{allow};
    my @allow;
    foreach my $ip (split(/[\s,]+/, $cfg->{allow})) {
        push @allow, Net::CIDR::range2cidr($ip)
    }

    return 0 unless Net::CIDR::cidrlookup($addr, @allow);
    return 1;
}

sub isEarlyLogin {
    return 0;
}

# Indicated whether we have to handle this request.
sub isMyLogin {
    0;
}

sub supportsRegistration {
    1;
}

sub getPid {
    my ( $this ) = @_;

    return $this->{internal_provider_id} if defined $this->{internal_provider_id};

    my $uauth = Foswiki::UnifiedAuth->new();
    my $pid = $uauth->getPid($this->{id});
    $this->{internal_provider_id} = $pid;

    return $pid;
}

sub processLogin {
    my ($this, $state) = @_;

    return 0;
}

sub processUrl {
    my $this = shift;
    my $session = $this->{session};
    return $session->getScriptUrl(1, 'login', undef, undef, @_);
}

sub origin {
    my ($this) = @_;

    return $this->{origin};
}

sub getDisplayAttributesOfLogin {
    my ($this, $login, $data) = @_;
    return 0;
}
1;
