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
    return $this;
}

sub isMyLogin {
    my $this = shift;
    my $cgis = $this->{session}->getCGISession;
    if ($cgis) {
        my $run = $cgis->param('uauth_kerberos_failed') || 0;
        return 0 if $run;
    }

    my $cfg = $this->{config};
    return 0 unless $cfg->{realm} && $cfg->{keytab};
    return 1;
}

sub isEarlyLogin {
    return 1;
}

sub initiateLogin {
    my ($this, $origin) = @_;
    my $req = $this->{session}{request};

    return $this->SUPER::initiateLogin($origin);
}

sub handleLogout {
    my ($this, $session) = @_;
    return unless $session;

    my $cgis = $session->getCGISession();
    $cgis->param('uauth_kerberos_logged_out', 1);
}

sub processLogin {
    my $this = shift;

    my $session = $this->{session};
    my $cgis = $session->getCGISession();
    return 0 if $cgis->param('uauth_kerberos_failed');
    return 0 if $cgis->param('uauth_kerberos_logged_out');

    my $req    = $session->{request};
    my $res = $session->{response};

    my $tried = $cgis->param('uauth_kerberos_run') || 0;
    if (!$tried) {
        $cgis->param('uauth_kerberos_run', 1);
        $cgis->param('uauth_provider', $this->{id});

        $res->deleteHeader('WWW-Authenticate');
        $res->header(-status => 401, -WWW_Authenticate => 'Negotiate');
        $res->body('');
        return 0;
    }

    my $cfg = $this->{config};
    my $token = $req->header('authorization') || '';
    $token =~ s/^Negotiate //;
    $token = decode_base64($token);

    if (length($token)) {
        $ENV{KRB5_KTNAME} = "FILE:$cfg->{keytab}";
        my $ctx;
        my $omech = GSSAPI::OID->new;
        my $status = GSSAPI::Context::accept(
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
        }

        my $principal;
        $status = $client->display($principal);

        unless ($principal) {
            $cgis->param('uauth_kerberos_failed', 1);
            return 0;
        }

        # ToDo. place an option in configure whether to strip off the realm
        $principal =~ s/\@$cfg->{realm}//;
        return $principal;
    }

    return 0;
}

1;
