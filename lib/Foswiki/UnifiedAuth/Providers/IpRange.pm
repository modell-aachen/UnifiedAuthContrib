package Foswiki::UnifiedAuth::Providers::IpRange;

use Error;

use strict;
use warnings;

use Foswiki::Plugins::UnifiedAuthPlugin;
use Foswiki::UnifiedAuth;
use Foswiki::UnifiedAuth::Provider;
our @ISA = qw(Foswiki::UnifiedAuth::Provider);

sub new {
    my ($class, $session, $id, $config) = @_;

    my $this = $class->SUPER::new($session, $id, $config);

    $config->{identityProvider} ||= '_all_';

    return $this;
}

sub forceButton {
    my ($this) = @_;

    return undef if defined $this->{config}->{forcable} && !$this->{config}->{forcable};

    return ($this->{config}->{loginIcon} || '<img src="%PUBURLPATH%/%SYSTEMWEB%/UnifiedAuthContrib/terminal.svg" />', $this->{config}->{loginDescription} || '%MAKETEXT{"Terminal login"}%');
}

sub isMyLogin {
    my $this = shift;
    my $forced = shift;

    my $cgis = $this->{session}->getCGISession;
    return 0 if $cgis->param("uauth_$this->{id}_logged_out") && !$forced && !$this->{config}->{ignoreLogout};

    # $this->enabled() did the rest for us...

    return 1;
}

sub isEarlyLogin {
    return 1;
}

sub processLogin {
    my $this = shift;

    my $config = $this->{config};
    return {identity => $config->{user_id}};
}

1;
