package Foswiki::UnifiedAuth::Providers::Topic;

use Error;
use JSON;
use Net::CIDR;
use Crypt::PBKDF2;

use strict;
use warnings;

use Foswiki::Plugins::UnifiedAuthPlugin;
use Foswiki::UnifiedAuth;
use Foswiki::UnifiedAuth::Provider;
use Foswiki::Users::TopicUserMapping;
use Foswiki::Users::UnifiedAuthUser;
use Foswiki::Users::HtPasswdUser;
our @ISA = qw(Foswiki::UnifiedAuth::Provider);

my @schema_updates = (
    [
        "INSERT INTO meta (type, version) VALUES('providers_topic', 0)",
        "INSERT INTO providers (name) VALUES('topic')",
    ]
);

sub new {
    my ($class, $session, $id, $config) = @_;

    my $this = $class->SUPER::new($session, $id, $config);

    # XXX no finish
    my $implPasswordManager = $this->{config}->{PasswordManager} || 'Foswiki::Users::UnifiedAuthUser';
    $implPasswordManager = 'Foswiki::Users::Password'
      if ( $implPasswordManager eq 'none' );
    eval "require $implPasswordManager";
    die $@ if $@;
    $this->{passwords} = $implPasswordManager->new($session);

    unless ( $this->{passwords}->readOnly() ) {
        $this->{session}->enterContext('passwords_modifyable');
    }

    return $this;
}

sub supportsRegistration {
    1; # TODO: check if PasswordManager allows registration
}

sub useDefaultLogin {
    1;
}

sub _generatePwHash {
    my $password = shift;

    my $pbkdf2 = Crypt::PBKDF2->new(
        hash_class => 'HMACSHA2',
        hash_args => {
            sha_size => 512,
        },
        iterations => 10000,
        salt_len => 10,
    );
    return $pbkdf2->generate($password);
}

sub setPassword {
    my ( $this, $login, $newUserPassword, $oldUserPassword ) = @_;

    if ( defined($oldUserPassword) ) {
        unless ( $oldUserPassword eq '1' ) {
            return undef unless $this->checkPassword( $login, $oldUserPassword );
        }
    }
    elsif ( $this->fetchPass($login) ) {
        $this->{error} = $login . ' already exists';
        return 0;
    }

    my $uauth = Foswiki::UnifiedAuth->new();
    # XXX UTF-8
    my $pwHash;
    if ($newUserPassword) {
        $pwHash = _generatePwHash($newUserPassword);
    }
    my $db = $uauth->db;
    my $userinfo = $db->selectrow_hashref("SELECT cuid, email, display_name, deactivated FROM users WHERE users.login_name=?", {}, $login);
    my $cuid = $uauth->update_user('UTF-8', $userinfo->{cuid}, $userinfo->{email}, $userinfo->{display_name}, $userinfo->{deactivated}, $pwHash);
    my $cgis = $this->{session}->getCGISession();
    $cgis->param('force_set_pw', 0);

    $this->{error} = undef;
    return 1;
}

sub refresh {
    my ( $this ) = @_;

    my $pid = $this->getPid();
    my $uauth = Foswiki::UnifiedAuth->new();
    my $topicMapping = Foswiki::Users::TopicUserMapping->new($this->{session});
    my $db = $uauth->db;

    my $topicPwManager = Foswiki::Users::HtPasswdUser->new($this->{session});
    if( $topicPwManager->canFetchUsers() ) {
        my $iter = $topicPwManager->fetchUsers();
        while ( $iter->hasNext() ) {
            my $login = $iter->next();
            # XXX
            my $cuid = $db->selectrow_array("SELECT cuid FROM users WHERE users.login_name=? AND users.pid=?", {}, $login, $pid);
            unless($cuid) {
                #Import user
                $cuid = $topicMapping->login2cUID($login);
                my $wikiname = $topicMapping->getWikiName($cuid);
                my @emails = $topicPwManager->getEmails($login);
                $this->addUser( $login, $wikiname, undef, \@emails, 1);
            }
        }
    }

}

sub addUser {
    my ( $this, $login, $wikiname, $password, $emails, $import ) = @_;

    # XXX not thread save
    # TODO: be transactional
    my $auth = Foswiki::UnifiedAuth->new();
    my $cuid;
    my $usedBy = $this->{session}->{users}->findUserByWikiName($wikiname);
    if($usedBy && scalar @$usedBy) {
        throw Error::Simple("Failed to add user: WikiName ($wikiname) already in use by: ".join(', ', @$usedBy));
    }
    $usedBy = $this->{session}->{users}->getLoginName($login);
    if($usedBy) {
        throw Error::Simple("Failed to add user: login ($login) already in use by $usedBy");
    }

    my $pid = $this->getPid();
    unless($pid) {
        throw Error::Simple("Failed to add user: TopicUserMapping mal-configured (could not get pid)");
    }

    if(ref $emails eq 'ARRAY') {
        $emails = $emails->[0];
    }
    unless($emails) {
        throw Error::Simple("Failed to add user: No email given for $wikiname");
    }
    if ($this->{passwords}->fetchPass($login) ) {

        # They exist; their password must match
        unless ( $this->{passwords}->checkPassword( $login, $password ) ) {
            throw Error::Simple(
                $this->{session}->i18n->maketext(
                    'User exists in the Password Manager,  and the password you provided is different from the users current password.   You cannot add a user and change the password at the same time.'
                )
            );
        }

        # User exists, and the password was good.
    } else {
        # add a new user

        unless ( defined($password) ) {
            require Foswiki::Users;
            $password = Foswiki::Users::randomPassword();
        }

        if(ref $emails eq 'ARRAY') {
            $emails = $emails->[0];
        }
        # XXX UTF-8
        my $pwHash;
        if (!$import && $password) {
            $pwHash = _generatePwHash($password);
        }
        $cuid = $auth->add_user('UTF-8', $pid, undef, $emails, $login, $wikiname, $wikiname, 0, $pwHash);
    }

    my $addedWikiName = $this->{session}->{users}->getWikiName($cuid);
    unless($addedWikiName eq $wikiname) {
        $auth->delete_user($cuid);
        throw Error::Simple("Failed to add user: WikiName ($wikiname) already in use");
    }
    return $cuid;
}

sub processLoginData {
    my ( $this, $login, $password ) = @_;

    my ($cuid, $change_password) = $this->_checkPassword($login, $password);
    return undef unless $cuid;

    if($change_password) {
        my $cgis = $this->{session}->getCGISession();
        $cgis->param('force_set_pw', 1);
    }

    return { cuid => $cuid, data => {} };
}

sub _checkPassword {
    my ( $this, $login, $password ) = @_;

    my $uauth = Foswiki::UnifiedAuth->new();
    my $db = $uauth->db;

    my $userinfo = $db->selectrow_hashref("SELECT cuid, wiki_name, password FROM users WHERE users.login_name=?", {}, $login);
    return undef unless $userinfo;
    my $change_password;
    if( $userinfo->{password} ) {
        my $pbkdf2 = Crypt::PBKDF2->new;
        return undef unless $pbkdf2->validate( $userinfo->{password}, $password );
    } else {
        my $topicPwManager = Foswiki::Users::HtPasswdUser->new($this->{session});
        return undef unless $topicPwManager->checkPassword( $userinfo->{wiki_name}, $password );
        $change_password = 1;
    }

    return ($userinfo->{cuid}, $change_password);
}

sub checkPassword {
    my ( $this, $login, $password ) = @_;

    my ($cuid) = $this->_checkPassword($login, $password);
    return ($cuid) ? 1 : undef;
}

1;

