package Foswiki::UnifiedAuth::Providers::Facebook;

use Error;
use JSON;

use strict;
use warnings;

use Foswiki::Func;
use Foswiki::Plugins::UnifiedAuthPlugin;
use Foswiki::UnifiedAuth;
use Foswiki::UnifiedAuth::Provider;
our @ISA = qw(Foswiki::UnifiedAuth::Provider);

my @schema_updates = (
    [
        "CREATE TABLE users_facebook (
            cuid UUID NOT NULL,
            info JSONB NOT NULL,
            PRIMARY KEY (cuid)
        )",
        "INSERT INTO meta (type, version) VALUES('users_facebook', 0)",
        "INSERT INTO providers (name) VALUES('facebook')",
    ]
);

sub forceButton {
    my ($this) = @_;

    return undef if defined $this->{config}->{forcable} && !$this->{config}->{forcable};

    my $icon;
    if($this->{config}->{loginIcon}){
        $icon = $this->{config}->{loginIcon};
    } else {
        $icon = $Foswiki::cfg{PubUrlPath}.'/'.$Foswiki::cfg{SystemWebName}.'/UnifiedAuthContrib/logo_facebook.svg';
    }
    my $description;
    if($this->{config}->{loginDescription}){
        $description = $this->{config}->{loginIcon};
    } else {
        $description = 'Login with Facebook';
    }
    return ($icon, $description);
}

sub new {
    my ($class, $session, $id, $config) = @_;
    my $this = $class->SUPER::new($session, $id, $config);
    return $this;
}

sub initiateLogin {
    my ($this, $origin) = @_;
    return 0;
}

sub isMyLogin {
    my $this = shift;
    return 0;
}

sub processLogin {
    my $this = shift;
}

1;
