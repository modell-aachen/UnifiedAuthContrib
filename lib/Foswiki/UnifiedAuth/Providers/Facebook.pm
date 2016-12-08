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

sub new {
    my ($class, $session, $id, $config) = @_;
    my $this = $class->SUPER::new($session, $id, $config);
    return $this;
}

sub initiateLogin {
    my ($this, $origin) = @_;
}

sub isMyLogin {
    my $this = shift;
}

sub processLogin {
    my $this = shift;
}

1;
