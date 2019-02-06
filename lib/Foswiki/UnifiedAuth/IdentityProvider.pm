package Foswiki::UnifiedAuth::IdentityProvider;

use strict;
use warnings;

use Foswiki::UnifiedAuth::Provider;
our @ISA = qw(Foswiki::UnifiedAuth::Provider);

sub new {
    my ($class, $session, $id, $config) = @_;
    my $this = $class->SUPER::new($session, $id, $config);
    return $this;
}

sub processLoginName {
  my ($this, $loginName) = @_;

  return $loginName;
}

sub identify {
    my $this = shift;
    my $login = shift;

    $login = $this->processLoginName($login);
    my $db = Foswiki::UnifiedAuth->new()->db;
    my $pid = $this->getPid;
    my $user = $db->selectrow_hashref("SELECT cuid, wiki_name FROM users WHERE users.login_name=? AND uac_disabled=0 AND deactivated=0 AND users.pid=?", {}, $login, $pid);

    return {cuid => $user->{cuid}, data => {}} if $user;
    return undef;
}
