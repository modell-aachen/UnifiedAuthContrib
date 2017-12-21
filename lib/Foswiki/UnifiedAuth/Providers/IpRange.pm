package Foswiki::UnifiedAuth::Providers::IpRange;

use Error;

use strict;
use warnings;

use Foswiki::Plugins::UnifiedAuthPlugin;
use Foswiki::UnifiedAuth;
use Foswiki::UnifiedAuth::Provider;
our @ISA = qw(Foswiki::UnifiedAuth::Provider);

my @schema_updates = (
    [
    ]
);

sub new {
    my ($class, $session, $id, $config) = @_;

    my $this = $class->SUPER::new($session, $id, $config);

    return $this;
}

sub isMyLogin {
    my $this = shift;

    # $this->enabled() did all the work for us...

    return 1;
}

sub isEarlyLogin {
    return 1;
}

sub processLogin {
    my $this = shift;

    my $config = $this->{config};
    my $login = $config->{user_id};
    return undef unless $login;

    my $db = Foswiki::UnifiedAuth->new()->db;
    my $pid = $this->getPid;

    my $user = $db->selectrow_hashref("SELECT cuid, wiki_name FROM users WHERE users.login_name=? AND users.pid=?", {}, $login, $pid);
    return {cuid => $user->{cuid}, data => {}} if $user;
    return undef;
}

1;
