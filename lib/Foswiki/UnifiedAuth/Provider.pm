package Foswiki::UnifiedAuth::Provider;

use Data::GUID;
use Digest::SHA qw(sha1_base64);
use Error;

use strict;
use warnings;

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

sub useDefaultLogin {
    my $this = shift;
    0;
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

sub processLogin {
    my ($this, $state) = @_;
    my $cgis = $this->{session}->getCGISession();
    die with Error::Simple("Login requires a valid session; do you have cookies disabled?") if !$cgis;
    my $saved = $cgis->param('uauth_state');
    return $saved eq $state;
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

sub guid {
    my $this = shift;
    Data::GUID->guid;
}

1;
