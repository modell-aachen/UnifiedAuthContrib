package Foswiki::UnifiedAuth::Providers::Steam;

use Error;
use JSON;
use LWP::UserAgent;
use Net::OpenID::Consumer;
use LWPx::ParanoidAgent;
use URI::Escape;
use Cache::FileCache;

use strict;
use warnings;

use Foswiki::Func;
use Foswiki::Plugins::UnifiedAuthPlugin;
use Foswiki::UnifiedAuth;
use Foswiki::UnifiedAuth::Provider;
our @ISA = qw(Foswiki::UnifiedAuth::Provider);

sub new {
    my ($class, $session, $id, $config) = @_;

    my $this = $class->SUPER::new($session, $id, $config);

    $this->{config}->{autoLogin} = 1 unless defined $this->{config}->{autoLogin};

    return $this;
}

sub _makeOpenId {
    my $this = shift;

    my $root = Foswiki::Func::getUrlHost();

    my $cgis = $this->{session}->getCGISession();
    my $secret = $cgis->param('steam_secret');
    unless($secret) {
        $secret = rand() . time();
        $cgis->param('steam_secret', $secret);
    }

    my $cache = new Cache::FileCache({
        namespace => $this->{id},
    });

    my $req = $this->{session}{request};
    my $args = sub {
        # putting a facade around this, to avoid want_array with param trouble
        if(scalar @_ && defined $_[0]) {
            return $req->param(@_);
        } else {
            return $req->param();
        }
    };

    my $csr = Net::OpenID::Consumer->new(
        ua => LWPx::ParanoidAgent->new(),
        cache => $cache,
        args => $args,
        consumer_secret => $secret,
        required_root => $root,
    );

    return $csr;
}

sub initiateExternalLogin {
    my $this = shift;
    my $state = shift;

    my $session = $this->{session};
    my $cgis = $this->{session}->getCGISession();
    my $root = Foswiki::Func::getUrlHost();
    my $login_script = Foswiki::Func::getScriptUrl(undef, undef, 'login', state => $state, steam_oid => 1);

    my $csr = $this->_makeOpenId;
    my $claimed_identity = $csr->claimed_identity("http://steamcommunity.com/openid");
    die "error with identity: ".$csr->err() unless $claimed_identity;

    my $check_url = $claimed_identity->check_url(
        return_to => $login_script,
        trust_root => $root,
        delayed_return => 1,
    );

    $this->{session}{response}->redirect(
        -url     => $check_url,
        -cookies => $session->{response}->cookies(),
        -status  => '302',
    );
    return 1;
}

sub forceButton {
    my ($this) = @_;

    return undef if defined $this->{config}->{forcable} && !$this->{config}->{forcable};

    my $icon;
    if($this->{config}->{loginIcon}){
        $icon = $this->{config}->{loginIcon};
    } else {
        $icon = $Foswiki::cfg{PubUrlPath}.'/'.$Foswiki::cfg{SystemWebName}.'/UnifiedAuthContrib/logo_steam.svg';
    }
    my $description;
    if($this->{config}->{loginDescription}){
        $description = $this->{config}->{loginIcon};
    } else {
        $description = 'Login with Steam';
    }
    return ($icon, $description);
}

sub initiateLogin {
    my ($this, $state, $forced) = @_;

    return 0 unless ($this->{config}->{autoLogin} || $forced);

    return $this->initiateExternalLogin($state);
}

sub isMyLogin {
    my $this = shift;

    my $req = $this->{session}{request};
    my $state = $req->param('state');

    return $state && $req->param('steam_oid');
}

sub processLogin {
    my $this = shift;

    my $req = $this->{session}{request};
    my $state = uri_unescape($req->param('state'));
    $req->delete('state');

    my $csr = $this->_makeOpenId;
    $req->delete('steam_oid');

    my $cuid;
    $csr->handle_server_response(
        not_openid => sub {
            Foswiki::Func::writeWarning("Not an openid message");
        },
        setup_needed => sub {
            Foswiki::Func::writeWarning("todo: setup_needed")
        },
        cancelled => sub {
            Foswiki::Func::writeWarning("Login cancelled");
        },
        verified => sub {
            my ($id) = @_;

            Foswiki::Func::writeWarning("Hello", $id->display());
            # TODO: Fetch userinfo using an API-key. I do not have such key, so
            # I will simply use the provided id for everything.
            die with Error::Simple("Invalid ID") unless $id->display() =~ m#/id/([0-9]+)/?$#;
            my $login = $1;

            my $pid = $this->getPid();
            my $uauth = Foswiki::UnifiedAuth->new();

            $cuid = $uauth->getCUIDByLoginAndPid($login, $pid);
            Foswiki::Func::writeWarning("cuid", $cuid, $login, $pid);
            return if $cuid;

            unless ( $this->{config}->{registerNewUsers} ) {
                Foswiki::Func::writeWarning("User is unknown: $login") if $this->{config}->{debug};
                return;
            }
            my $wiki_name = "SteamUser$login";
            $cuid = $uauth->add_user(undef, $pid, {
                email => '',
                login_name => $login,
                wiki_name => $wiki_name,
                display_name => $login
            });
            Foswiki::Func::writeWarning("New steam user: $login ($cuid)");
        },
        error => sub {
            my ($errorcode, $errtext ) = @_;
            Foswiki::Func::writeWarning("error: $errorcode $errtext");
        },
    );

    $req->delete('state', 'steam_oid', 'oic.time', 'openid.ns', 'openid.mode', 'openid.op_endpoint', 'openid.claimed_id', 'openid.identity', 'openid.return_to', 'openid.response_nonce', 'openid.assoc_handle', 'openid.signed', 'openid.sig');

    return { cuid => $cuid } if $cuid;

    Foswiki::Func::writeWarning("Steam login failed", $cuid) if $this->{config}->{debug};
    return undef;
}

1;
