package Foswiki::UnifiedAuth::Provider;

use strict;
use warnings;

use Digest::SHA qw(sha1_base64);
use Error;
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
    $cgis->param('uauth_state', $state) unless $cgis->param('uauth_state');
    $cgis->param('uauth_provider', $this->{id});
    $cgis->flush;
    die $cgis->errstr if $cgis->errstr;
    return $state;
}

sub refresh {
    # my ( $this ) = @_;
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
    my $db = $uauth->db;
    my $pid = $db->selectrow_array("SELECT pid FROM providers WHERE name=?", {}, $this->{id});

    if ($pid) {
        $this->{internal_provider_id} = $pid;
        return $pid;
    }

    Foswiki::Func::writeWarning("Could not get pid of $this->{id}; creating a new one...");
    $db->do("INSERT INTO providers (name) VALUES(?)", {}, $this->{id});
    return $this->getPid();
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

1;
