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

    my $icon;
    if($this->{config}->{loginIcon}){
        $icon = $this->{config}->{loginIcon};
    } else {
        $icon = $Foswiki::cfg{PubUrlPath}.'/'.$Foswiki::cfg{SystemWebName}.'/UnifiedAuthContrib/terminal.svg';
    }
    my $description;
    if($this->{config}->{loginDescription}){
        $description = $this->{config}->{loginIcon};
    } else {
        $description = 'Terminal login';
    }
    return ($icon, $description);
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
