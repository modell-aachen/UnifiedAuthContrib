package Foswiki::UnifiedAuth::Providers::Kerberos;

use strict;
use warnings;

use Error;
use GSSAPI;
use JSON;
use MIME::Base64;
use Net::CIDR;

use Foswiki::UnifiedAuth;
use Foswiki::UnifiedAuth::Provider;
our @ISA = qw(Foswiki::UnifiedAuth::Provider);

sub new {
    my ($class, $session, $id, $config) = @_;
    my $this = $class->SUPER::new($session, $id, $config);
    return $this;
}

sub enabled {
    my $this = shift;
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

sub isMyLogin {
    my $this = shift;

    my $req = $this->{session}{request};
    my $addr = $req->remote_addr;

    if ($this->{config}->{deny}) {
        my @deny;
        foreach my $ip (split(/[\s,]+/, $this->{config}->{deny})) {
            push @deny, Net::CIDR::range2cidr($ip);
        }

        return 0 if Net::CIDR::cidrlookup($addr, @deny);
    }

    return 1 unless $this->{config}->{allow};
    my @allow;
    foreach my $ip (split(/[\s,]+/, $this->{config}->{allow})) {
        push @allow, Net::CIDR::range2cidr($ip)
    }

    return 0 unless Net::CIDR::cidrlookup($addr, @allow);
    return 1;
}

sub processLogin {
    my $this = shift;

    my $session = $this->{session};
    my $cgis = $session->getCGISession();
    return 0 if $cgis->param('uauth_kerberos_failed');

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

        # if ($otoken) {
        #     my $enc = encode_base64($otoken);
        # }

        my $principal;
        $status = $client->display($principal);

        unless ($principal) {
            $cgis->param('uauth_kerberos_failed', 1);
            return 0;
        }

        $principal =~ s/\@$cfg->{realm}//;
        return $principal;
    }

    return 0;
}

1;
