package Foswiki::UnifiedAuth::Providers::Cas;

use Error;
use JSON;
use AuthCAS;
use URI::Escape;

use strict;
use warnings;

use Foswiki::Func;
use Foswiki::Plugins::UnifiedAuthPlugin;
use Foswiki::UnifiedAuth;
use Foswiki::UnifiedAuth::Provider;
our @ISA = qw(Foswiki::UnifiedAuth::Provider);

my @schema_updates = (
    [
        "CREATE TABLE IF NOT EXISTS users_cas (
            cuid UUID NOT NULL,
            pid INTEGER NOT NULL,
            info JSONB NOT NULL,
            PRIMARY KEY (cuid)
        )",
        "INSERT INTO meta (type, version) VALUES('users_cas', 0)"
    ]
);

sub new {
    my ($class, $session, $id, $config) = @_;

    my $this = $class->SUPER::new($session, $id, $config);

    $this->{config}->{autoLogin} = 1 unless defined $this->{config}->{autoLogin};
    $this->{config}->{identityProvider} = '_all_' unless defined $this->{config}->{identityProvider};

    return $this;
}

sub _getCas {
    my ($this) = @_;

    return new AuthCAS(
        casUrl      => $this->{config}{casUrl},
        CAFile      => $this->{config}{CAFile},
        SSL_version => $this->{config}{SSL_version},
    );
}

# Will either redirect us to the logout page of our cas or simply set a flag
# that prevents us from simply logging in again.
sub handleLogout {
    my ($this, $session, $user) = @_;
    return unless $session;

    if($this->{config}{LogoutFromCAS}) {
        # redirect to cas logout page
        $session->redirect($this->_getLogoutUrl());
    } else {
        my $cgis = $session->getCGISession();
        $cgis->param("uauth_$this->{id}_logged_out", 1);
    }
}

# Will redirect us to the cas provider.
sub initiateExternalLogin {
    my ($this, $state) = @_;

    my $session = $this->{session};
    my $cgis = $this->{session}->getCGISession();
    $cgis->param("cas_$this->{id}_attempted", 1);

    my $cas = $this->_getCas();

    my $casurl = $cas->getServerLoginURL($this->_fwLoginScript($state));

    $this->{session}{response}->redirect(
        -url     => $casurl,
        -cookies => $session->{response}->cookies(),
        -status  => '302',
    );
    return 1;
}

sub forceButton {
    my ($this) = @_;

    return undef if defined $this->{config}->{forcable} && !$this->{config}->{forcable};

    return ($this->{config}->{loginIcon} || '<img src="%PUBURLPATH%/%SYSTEMWEB%/UnifiedAuthContrib/corporate.svg" style="height: 20; width: 16;" />', $this->{config}->{loginDescription} || '%MAKETEXT{"Corporate login"}%');
}

sub initiateLogin {
    my ($this, $state, $forced) = @_;

    my $cgis = $this->{session}->getCGISession;

    unless($forced) {
        return 0 unless $this->{config}->{autoLogin};
        return 0 if $cgis->param("uauth_$this->{id}_logged_out");
        return 0 if $cgis->param("cas_$this->{id}_attempted");
    } else {
        $cgis->clear("uauth_$this->{id}_logged_out", "cas_$this->{id}_attempted");
    }

    return $this->initiateExternalLogin($state);
}

# We always claim this is our login, because if nobody is logged in, we want to
# redirect to our cas provider - unless the user explicitly logged out.
sub isMyLogin {
    my $this = shift;
    my $forced = shift;

    my $req = $this->{session}{request};

    my $cgis = $this->{session}->getCGISession();
    return 0 if $cgis->param("uauth_$this->{id}_logged_out") && !$forced;

    return $req->param('cas_login');
}

sub isEarlyLogin {
    return 1;
}

sub processLogin {
    my $this = shift;

    my $req = $this->{session}{request};
    my $state = $req->param('state');
    my $ticket = $req->param('ticket');
    my $iscas_login = $req->param('cas_login');

    # down below we will delete cas_attempted, but only if the login was
    # successful, so we do not redirect in circles
    $req->delete('state', 'cas_login', 'ticket');

    unless($state && $ticket) {
        die with Error::Simple("You seem to be using an outdated URL. Please try again.\n");
    }

    my $cas = $this->_getCas();
    my $casUser = $cas->validateST( $this->_fwLoginScript($state), $ticket );
    unless ($casUser) {
        die with Error::Simple("CAS login failed (could not validate). Please try again.\n");
    }

    if (   $Foswiki::cfg{CAS}{AllowLoginUsingEmailAddress} && $casUser =~ /@/ ) {
        my $login = $this->{session}->{users}->findUserByEmail($casUser);
        $casUser = $login->[0] if ( defined( $login->[0] ) );
    }

    my $uauth = Foswiki::UnifiedAuth->new();
    my $db = $uauth->db;
    my $pid = $this->getPid();
    $uauth->apply_schema('users_cas', @schema_updates);

    $req->delete("cas_$this->{id}_attempted");

    return {identity => $casUser, state => $state};
}

# Generate a login-url we can redirect to.
# It should contain our state and the cas_login marker. Also it will include a
# cas_attempted flag, which stops us redirecting if anything goes wrong.
sub _fwLoginScript {
    my ($this, $state) = @_;

    # Note: in total we need to escape the state twice, because one will be
    # consumed by the redirect from cas
    my $state_escaped = uri_escape($state || '');

    my $login_script = Foswiki::Func::getScriptUrl(undef, undef, 'login', 'cas_login' => 1, "cas_$this->{id}_attempted" => 1, state => $state);

    return uri_escape($login_script);
}

# Get url we need to redirect to in order to log out from cas.
sub _getLogoutUrl {
    my $this = shift;

    my $session = $this->{session};
    my $req = $session->{request};
    my $uri = Foswiki::Func::getUrlHost() . $req->uri();

    #remove any urlparams, as they will be in the cachedQuery
    $uri =~ s/\?.*$//;
    return $this->_getCas()->getServerLogoutURL(
        Foswiki::urlEncode( $uri . $session->cacheQuery() )
    );
}
1;
