package Foswiki::UnifiedAuth::Providers::Kerberos;

use strict;
use warnings;

use Error;
use GSSAPI;
use JSON;
use MIME::Base64;

use Foswiki::UnifiedAuth;
use Foswiki::UnifiedAuth::Provider;
our @ISA = qw(Foswiki::UnifiedAuth::Provider);

sub new {
    my ($class, $session, $id, $config) = @_;
    my $this = $class->SUPER::new($session, $id, $config);

    $this->{config}->{identityProvider} = '_all_' unless defined $this->{config}->{identityProvider};
    $this->{config}->{autoLogin} = 1 unless defined $this->{config}->{autoLogin};

    return $this;
}

sub forceButton {
    my ($this) = @_;

    return undef if defined $this->{config}->{forcable} && !$this->{config}->{forcable};

    return ($this->{config}->{loginIcon} || '<img src="%PUBURLPATH%/%SYSTEMWEB%/UnifiedAuthContrib/corporate.svg" style="height: 20; width: 16;" />', $this->{config}->{loginDescription} || '%MAKETEXT{"Corporate login"}%');
}

sub isMyLogin {
    my $this = shift;
    my $forced = shift;

    my $req = $this->{session}->{request};
    my $cgis = $this->{session}->getCGISession;
    return 0 unless $cgis;

    return 0 if ($cgis->param("uauth_$this->{id}_failed") || $cgis->param("uauth_$this->{id}_logged_out"))  && !$forced; # Note: browser might add authorization token, even if we did not ask for it in initiateLogin

    my $token = $req->header('authorization');
    unless (defined $token) {
        if($cgis->param("uauth_$this->{id}_run")) {
            my $message = "Client did not send an authorization token, please add wiki to 'Local intranet'";
            Foswiki::Func::writeWarning($message) if $this->{config}->{debug};
            throw Error::Simple($this->{session}->i18n->maketext($message));
        }
        return 0;
    }

    return 1;
}

sub isEarlyLogin {
    return 1;
}

sub initiateLogin {
    my ($this, $state, $forced) = @_;

    my $cgis = $this->{session}->getCGISession();

    unless ($this->{config}->{realm} && $this->{config}->{keytab}) {
        Foswiki::Func::writeWarning("Please specify realm and keytab in configure") if $this->{config}->{debug};
        return $Foswiki::UnifiedAuth::Provider::INITIATE_LOGIN_CONTINUE;
    }

    if($forced) {
        $cgis->clear(["uauth_$this->{id}_failed", "uauth_$this->{id}_logged_out"]);
    } else {
        return $Foswiki::UnifiedAuth::Provider::INITIATE_LOGIN_CONTINUE unless $this->{config}->{autoLogin};
        if ($cgis->param("uauth_$this->{id}_failed")) {
            Foswiki::Func::writeWarning("Skipping Kerberos $this->{id}, because it failed before") if $this->{config}->{debug};
            return $Foswiki::UnifiedAuth::Provider::INITIATE_LOGIN_CONTINUE;
        }
        if ($cgis->param("uauth_$this->{id}_logged_out")) {
            Foswiki::Func::writeWarning("Skipping Kerberos $this->{id}, because user logged out") if $this->{config}->{debug} && $this->{config}->{debug} eq 'verbose';
            return $Foswiki::UnifiedAuth::Provider::INITIATE_LOGIN_CONTINUE;
        }
    }

    Foswiki::Func::writeWarning("Asking for kerberos authentification") if $this->{config}->{debug} && $this->{config}->{debug} eq 'verbose';
    $cgis->param("uauth_$this->{id}_run", 1);

    my $res = $this->{session}->{response};
    $res->deleteHeader('WWW-Authenticate');
    $res->header(-status => 401, -WWW_Authenticate => 'Negotiate');
    $res->body('');
    # XXX
    # Unfortunately the user will be presented with an empty page when all
    # these conditions apply (Edge bug?):
    #    * Edge
    #    * not configured for kerberos (local sites)
    #    * user presses 'esc' when NTLM challenge appears
    # This is not because of the body(''), rather the browser gets a
    # complete page but chooses to ignore the body.

    return $Foswiki::UnifiedAuth::Provider::INITIATE_LOGIN_RENDERDEFAULT;
}

sub processLogin {
    my $this = shift;

    my $session = $this->{session};
    my $cgis = $session->getCGISession();
    my $cfg = $this->{config};


    my $req = $session->{request};
    my $res = $session->{response};

    my $token = $req->header('authorization'); # existence was checked in 'isMyLogin'

    $token =~ s/^Negotiate //;
    if ($token =~ m#^TlRMT#) {
        # have it not use NTLM anymore
        $res->deleteHeader('WWW-Authenticate');
        $res->header(-status => 401);

        Foswiki::Func::writeWarning("Client attempted authorization with a NTLM token. Please add wiki to 'Local intranet'.") if $cfg->{debug};
        my $error = $session->i18n->maketext("Your browser is not correctly configured for the authentication with this wiki. Please add this site to your 'local intranet'. Please contact your administrator for further assistance.");
        $res->deleteHeader('WWW-Authenticate');
        throw Error::Simple($error);
    }
    $token = decode_base64($token);

    if (length($token)) {
        $ENV{KRB5_KTNAME} = "FILE:$cfg->{keytab}";
        my $ctx;
        my $accept_status = GSSAPI::Context::accept(
            $ctx,
            GSS_C_NO_CREDENTIAL,
            $token,
            GSS_C_NO_CHANNEL_BINDINGS,
            my $client,
            gss_nt_krb5_name,
            my $otoken,
            my $oflags,
            my $otime,
            my $delegated
        );

        if ($otoken) {
            my $enc = encode_base64($otoken);
            $res->deleteHeader('WWW-Authenticate');
            $res->header(-WWW_Authenticate => "Negotiate $enc");
            Foswiki::Func::writeWarning("Adding otoken to response") if $cfg->{debug} && $cfg->{debug} eq 'verbose';
        }

        my $principal;
        my $client_status = $client->display($principal);
        unless ($principal) {
            if($cfg->{debug}) {
                if($accept_status->major()) {
                    Foswiki::Func::writeWarning($accept_status);
                } else {
                    Foswiki::Func::writeWarning($client_status) if $client_status->major();
                }
            }
            $cgis->param('uauth_kerberos_failed', 1);
            my $error = $session->i18n->maketext("The authentication failed (Kerberos error). Please contact your administrator for further assistance.");
            throw Error::Simple($error);
        }

        $principal = Encode::decode_utf8($principal);
        $principal =~ s/\@$cfg->{realm}// unless $this->{config}->{identifyWithRealm};
        Foswiki::Func::writeWarning("Kerberos identified user as '$principal'") if $cfg->{debug};
        return {identity => $principal};
    }

    Foswiki::Func::writeWarning("Client sent malformed authorization token");
    return 0;
}

1;
