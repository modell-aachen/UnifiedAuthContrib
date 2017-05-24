package Foswiki::UnifiedAuth::Provider;

use JSON;
use strict;
use warnings;

use Foswiki::UnifiedAuth;

use Digest::SHA qw(sha1_base64);
use Error qw( :try );
use Net::CIDR;

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

sub handleLogout {
    # Static method
    # Called by UnifiedLoading::loadSession when the user logged out
}
# Add user to provider.
# Return cuid if successful, perl-false otherwise.
sub addUser {
    return undef;
}

sub useDefaultLogin {
    return 0;
}

sub initiateLogin {
    my ($this, $origin) = @_;

    my $cgis = $this->{session}->getCGISession();
    die with Error::Simple("Login requires a valid session; do you have cookies disabled?") if !$cgis;

    my $csrf = sha1_base64(rand(). "$$ $0");
    my $state = "$csrf,uauth,$origin";
    $cgis->param('uauth_state', $state);
    $cgis->param('uauth_provider', $this->{id});
    $cgis->flush;
    die $cgis->errstr if $cgis->errstr;
    return $state;
}

sub indexUser {
    my ( $this, $cuid ) = @_;

    $this->refresh($cuid);
}

sub refresh {
    my ( $this, $cuid ) = @_;

    return 1 unless $Foswiki::cfg{Plugins}{SolrPlugin}{Enabled};

    require Foswiki::Plugins::SolrPlugin;
    my $indexer = Foswiki::Plugins::SolrPlugin::getIndexer();

    my $uauth = Foswiki::UnifiedAuth->new();
    my $db = $uauth->db;
    my $pid = $this->getPid();

    my $userQuery;
    if($cuid){
        $userQuery = "SELECT * FROM users WHERE cuid='$cuid' pid=?";
    }
    else{
        $userQuery = "SELECT * FROM users WHERE pid=?";
    }

    my $users = $db->selectall_arrayref($userQuery, {Slice => {}}, $pid);
    foreach my $user (@$users) {
        my $groups = $db->selectall_arrayref("select group_members.g_cuid,providers.name as provider_name,groups.name as group_name from group_members inner join groups on (group_members.g_cuid=groups.cuid) inner join providers on (groups.pid=providers.pid) WHERE u_cuid=?", {Slice => {}}, $user->{cuid});
        my @groupIds = map { $_->{g_cuid} } @$groups;
        my @groupNames = map { $_->{group_name} } @$groups;
        my @groupProviders = map { $_->{provider_name} } @$groups;

        my $userdoc = $indexer->newDocument();
        $userdoc->add_fields(
          'id' => $user->{cuid},
          'type' => 'ua_user',
          'cuid_s' => $user->{cuid},
          'loginname_s' => $user->{login_name},
          'wikiname_s' => $user->{wiki_name},
          'displayname_s' => $user->{display_name},
          'email_s' => $user->{email} || '',
          'mainprovidername_s' => $this->{id},
          'providers_lst' => [$this->{id}],
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

# members


    # my $grpdoc = $indexer->newDocument();
    # $grpdoc->add_fields(
    #   'id' => "todo_guid_here",
    #   'type' => 'ua_grp',
    # );

    # try {
    #     $indexer->add($grpdoc);
    # } catch Error::Simple with {
    #     my $e = shift;
    #     $indexer->log("ERROR: ".$e->{-text});
    # };
}

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
    my $cgis = $this->{session}->getCGISession();
    die with Error::Simple("Login requires a valid session; do you have cookies disabled?") if !$cgis;
    my $saved = $cgis->param('uauth_state') || '';
    return $saved eq ($state || '');
}

sub processUrl {
    my $this = shift;
    my $session = $this->{session};
    return $session->getScriptUrl(1, 'login');
}

sub origin {
    my $this = shift;

    my $cgis = $this->{session}->getCGISession();
    die with Error::Simple("Login requires a valid session; do you have cookies disabled?") if !$cgis;

    my $state = $cgis->param('uauth_state');
    return unless $state && $state =~ /^(.+?),(.+?),(.*)$/;
    return $3;
}

sub getDisplayAttributesOfLogin {
    my ($this, $login, $data) = @_;
    return 0;
}
1;
