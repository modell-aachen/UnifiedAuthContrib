package Foswiki::UnifiedAuth::Providers::EnvVar;

use strict;
use warnings;

use Foswiki::UnifiedAuth;
use Foswiki::UnifiedAuth::Provider;
our @ISA = qw(Foswiki::UnifiedAuth::Provider);

sub new {
    my ($class, $session, $id, $config) = @_;
    my $this = $class->SUPER::new($session, $id, $config);

    $this->{config}->{identityProvider} = '_all_' unless defined $this->{config}->{identityProvider};
    $this->{config}->{autoLogin} = 1 unless defined $this->{config}->{autoLogin};
    $this->{config}->{header} ||= 'X-Remote-User';

    return $this;
}

sub isMyLogin {
    my $this = shift;
    my $forced = shift;
    my $cgis = $this->{session}->getCGISession;

    if ($cgis->param("uauth_$this->{id}_logged_out") && !$forced) {
        Foswiki::Func::writeWarning("Skipping EnvVar, because user logged out.") if $this->{config}->{debug} && $this->{config}->{debug} eq 'verbose';
        return 0;
    }

    my $req = $this->{session}{request};
    my $envvar = $req->header($this->{config}->{header});

    unless (defined $envvar) {
        Foswiki::Func::writeWarning("$this->{config}->{header} header not set in client request.") if $this->{config}->{debug};
        return 0;
    }
    return 1;
}

sub forceButton {
    my ($this) = @_;

    return undef if defined $this->{config}->{forcable} && !$this->{config}->{forcable};

    my $icon;
    if($this->{config}->{loginIcon}){
        $icon = $this->{config}->{loginIcon};
    } else {
        $icon = $Foswiki::cfg{PubUrlPath}.'/'.$Foswiki::cfg{SystemWebName}.'/UnifiedAuthContrib/corporate.svg';
    }
    my $description;
    if($this->{config}->{loginDescription}){
        $description = $this->{config}->{loginIcon};
    } else {
        $description = 'Corporate login';
    }
    return ($icon, $description);
}

sub isEarlyLogin {
    return 1;
}

sub processLogin {
    my $this = shift;

    my $session = $this->{session};
    my $cgis = $session->getCGISession();
    my $cfg = $this->{config};

    my $req = $session->{request};
    my $res = $session->{response};

    my $header = $this->{config}->{header};
    my $envvar = $req->header($header);
    unless (defined $envvar) {
        Foswiki::Func::writeWarning("$header header not set in client request.") if $cfg->{debug};
        return 0;
    }

    my $realm = $this->{config}->{realm} || '';
    $envvar =~ s/\@$realm//;

    Foswiki::Func::writeWarning("User '$envvar' logged in by header $header.") if $cfg->{debug};
    return { identity => $envvar };
}

1;
