package Foswiki::UnifiedAuth::Providers::MSOnline;

use Error;
use JSON;
use LWP::UserAgent;
use URI::Escape;
use Digest::SHA qw(sha1_base64);
use MIME::Base64 qw( decode_base64 );

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
    $this->{config}->{identityProvider} = '_all_' unless defined $this->{config}->{identityProvider};

    return $this;
}

sub forceButton {
    my ($this) = @_;

    return undef if defined $this->{config}->{forcable} && !$this->{config}->{forcable};

    return ($this->{config}->{loginIcon} || '<img src="%PUBURLPATH%/%SYSTEMWEB%/UnifiedAuthContrib/logo_office.svg"/>', $this->{config}->{loginDescription} || '%MAKETEXT{"Login with Office 365"}%');
}

sub isEarlyLogin {
    return 1;
}

sub initiateExternalLogin {
    my ($this, $state) = @_;

    my $secret = $this->generateSecret($this->_getPrefix(), $state);

    unless ($this->{config}->{client_secret}) {
        Foswiki::Func::writeWarning("Please configure 'client_secret'");
        return 0;
    }

    my $tenant = $this->{config}->{tenant} || 'common';

    my $redirectUri = Foswiki::Func::getScriptUrl(undef, undef, 'login');
    Foswiki::Func::writeWarning("RedirectUri: '$redirectUri'") if $this->{config}->{debug};
    $redirectUri = uri_escape($redirectUri);

    my $uri = "https://login.microsoftonline.com/$tenant/oauth2/authorize?client_id=$this->{config}{client_id}&response_type=code&redirect_uri=$redirectUri&response_mode=query&state=$secret&resource=$this->{config}->{client_id}";
    Foswiki::Func::writeWarning("Sending user off to '$uri'") if $this->{config}->{debug};

    $this->{session}{response}->redirect(
        -url     => $uri,
        -status  => '302',
    );

    my $cgis = $this->{session}->getCGISession;
    $cgis->param("uauth_$this->{id}_attempted", 1);

    return 1;
}

sub initiateLogin {
    my ($this, $state, $forced) = @_;

    my $cgis = $this->{session}->getCGISession;

    unless($forced) {
        return 0 unless $this->{config}->{autoLogin};
        return 0 if $cgis->param("uauth_$this->{id}_logged_out");
        return 0 if $cgis->param("uauth_$this->{id}_attempted");
    } else {
        $cgis->clear("uauth_$this->{id}_logged_out", "uauth_$this->{id}_attempted");
    }

    return $this->initiateExternalLogin($state);
}

sub isMyLogin {
    my $this = shift;
    my $forced = shift;
    my $req = $this->{session}{request};

    my $state = $req->param('state');
    my $prefix = $this->_getPrefix();
    return $state && $state =~ m#^\Q$prefix\E#;
}

# Because we can not add our own parameters to the callback, we use the state
# with this prefix to determine, if this is actually our login:
sub _getPrefix {
    my $this = shift;

    return "uauth_$this->{id}_";
}

sub processLogin {
    my $this = shift;

    # Unfortunately using the LWP::Authen::OAuth2 or Net::Auth2 modules did not
    # succeed, because they did not encode the information in a way, that was
    # accepted my microsoftonline:
    # AADSTS90014: The request body must contain the following parameter: 'code'
    # So we unfortunately must do it ourselves.

    my $req = $this->{session}{request};

    my $secret = $req->param('state');
    my $state = $this->validateSecret($secret);
    my $code = $req->param('code');
    my $error = $req->param('error');
    $req->delete('state');
    $req->delete('code');
    $req->delete('error');

    if($error || !$code) {
        my $description = $req->param('error_description') || '(no details provided)';
        $error = 'no code was provided' unless $error || $code;
        $req->delete('error_description');
        Foswiki::Func::writeWarning("User came back with an error: ($error) $description") if $this->{config}->{debug};
        die with Error::Simple($this->{session}->i18n->maketext("There was an error while logging you in: ([_1]) [_2]", $error, $description));
    }

    unless ($state) {
        Foswiki::Func::writeWarning("Could not validate secret") if $this->{config}->{debug};
        die with Error::Simple($this->{session}->i18n->maketext("You seem to be using an outdated URL. Please try again."));
    }

    my $tenant = $this->{config}->{tenant} || 'common';
    my $redirectUri = Foswiki::Func::getScriptUrl(undef, undef, 'login');

    my $lwp = LWP::UserAgent->new;
    sub asContent {
        my %params = @_;
        my @content = ();
        foreach my $key (keys %params) {
            push @content, $key . '=' . uri_escape($params{$key});
        }
        return join('&', @content);
    }

    my $resp = $lwp->post("https://login.microsoftonline.com/$tenant/oauth2/token",
        Content => [
            client_id => $this->{config}->{client_id},
            client_secret => $this->{config}->{client_secret},
            code => $code,
            state => $secret,
            redirect_uri => $redirectUri,
            grant_type => 'authorization_code',
            resource => $this->{config}->{client_id},
        ],
    );

    unless ($resp->is_success) {
        Foswiki::Func::writeWarning("Could not request token", $resp->decoded_content) if $this->{config}->{debug};
        die with Error::Simple($resp->status_line);
    }

    my $data;
    eval {
        $data = from_json($resp->decoded_content);
    };
    if($@) {
        Foswiki::Func::writeWarning("Could not decode response when redeeming token", $@, $resp->decoded_content);
        die with Error::Simple($this->{session}->i18n->maketext("Could not read user data"));
    }

    if(!$data->{id_token}) {
        Foswiki::Func::writeWarning("Response is missing id_token", $resp->decoded_content);
        die with Error::Simple($this->{session}->i18n->maketext("Did not receive user data"));
    }
    # This is a JSON Web Token http://self-issued.info/docs/draft-ietf-oauth-json-web-token.html
    my ($headerBase64, $claimBase64, $junkBase64) = split(/\./, $data->{id_token});
    my $userData;
    eval {
        my $decoded = decode_base64($claimBase64);
        $userData = from_json($decoded);
    };
    if($@) {
        Foswiki::Func::writeWarning("Could not decode id_token", $@, $data->{id_token});
        die with Error::Simple($this->{session}->i18n->maketext("Unable to decode user data"));
    }

    my $uniqueName = $userData->{unique_name};
    if(!$uniqueName) {
        Foswiki::Func::writeWarning("Did not receive unique_name", $data->{id_token});
    }

    return unless $uniqueName =~ m#(.*)@(.*)#;
    my $identity = $1;
    my $domain = $2;

    if($this->{config}->{domains}) {
        my $domains = $this->{config}->{domains};
        $domains = [$domains] unless ref $domains;
        foreach my $validDomain (@{$domains}) {
            next unless lc( $domain ) eq lc( $validDomain );

            Foswiki::Func::writeWarning("User $identity from $domain logged in with $this->{id}") if $this->{config}->{debug};

            my $identity = $uniqueName;
            $identity =~ s/\@.*// unless $this->{config}->{identifyWithRealm};
            return {identity => $identity, state => $state};
        }
    } else {
        Foswiki::Func::writeWarning("User $uniqueName logged in with $this->{id}") if $this->{config}->{debug};

        return {identity => $uniqueName, state => $state};
    }

    Foswiki::Func::writeWarning("User $uniqueName not valid in $this->{id}") if $this->{config}->{debug};
    die with Error::Simple($this->{session}->i18n->maketext("Your login is not allowed in this wiki. Please contact your administrator for further assistance."));
}

1;
