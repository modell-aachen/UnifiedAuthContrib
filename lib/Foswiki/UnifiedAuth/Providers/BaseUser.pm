package Foswiki::UnifiedAuth::Providers::BaseUser;

use strict;
use warnings;

use DBI;
use Encode;
use Error;
use JSON;

use Foswiki::Func;
use Foswiki::Plugins::UnifiedAuthPlugin;
use Foswiki::UnifiedAuth;
use Foswiki::UnifiedAuth::Provider;
use Foswiki::Users::BaseUserMapping;

our @ISA = qw(Foswiki::UnifiedAuth::Provider);

Foswiki::Users::BaseUserMapping->new($Foswiki::Plugins::SESSION) if $Foswiki::Plugins::SESSION;
my $bu = \%Foswiki::Users::BaseUserMapping::BASE_USERS;

our $cuids = {
    BaseUserMapping_111 => 'aafd6652-3181-4845-b615-4bb7b970ca69',
    BaseUserMapping_222 => 'dc9f6b91-3762-4343-89e6-5d0795e85805',
    BaseUserMapping_333 => '3abfa98b-f92b-42ab-986e-872abca52a49',
    BaseUserMapping_666 => '09c180b0-fc8b-4f2c-a378-c09ccf6fb9f9',
    BaseUserMapping_999 => '40dda76a-1207-400f-b234-69da71ac405b'
};

my @schema_updates = (
    [
        "CREATE TABLE users_baseuser (
            cuid UUID NOT NULL,
            info JSONB NOT NULL,
            PRIMARY KEY (cuid)
        )",
        "INSERT INTO users_baseuser (cuid, info)
            VALUES
                ('$cuids->{BaseUserMapping_111}', '{\"wikiname\": \"$bu->{BaseUserMapping_111}{wikiname}\", \"description\": \"Project Contributor\"}'),
                ('$cuids->{BaseUserMapping_222}', '{\"wikiname\": \"$bu->{BaseUserMapping_222}{wikiname}\", \"description\": \"Registration Agent\"}'),
                ('$cuids->{BaseUserMapping_333}', '{\"wikiname\": \"$bu->{BaseUserMapping_333}{wikiname}\", \"description\": \"Internal Admin User\", \"email\": \"$bu->{BaseUserMapping_333}{email}\"}'),
                ('$cuids->{BaseUserMapping_666}', '{\"wikiname\": \"$bu->{BaseUserMapping_666}{wikiname}\", \"description\": \"Guest User\"}'),
                ('$cuids->{BaseUserMapping_999}', '{\"wikiname\": \"$bu->{BaseUserMapping_999}{wikiname}\", \"description\": \"Unknown User\"}')",
        "INSERT INTO meta (type, version) VALUES('users_baseuser', 0)",
        "INSERT INTO providers (pid, name) VALUES(0, 'baseuser')",
        "INSERT INTO users (cuid, pid, login_name, wiki_name, display_name, email)
            VALUES
                ('$cuids->{BaseUserMapping_111}', 0, '$bu->{BaseUserMapping_111}{login}', '$bu->{BaseUserMapping_111}{wikiname}', 'Project Contributor', ''),
                ('$cuids->{BaseUserMapping_222}', 0, '$bu->{BaseUserMapping_222}{login}', '$bu->{BaseUserMapping_222}{wikiname}', 'Registration Agent', ''),
                ('$cuids->{BaseUserMapping_333}', 0, '$bu->{BaseUserMapping_333}{login}', '$bu->{BaseUserMapping_333}{wikiname}', 'Internal Admin User', '$bu->{BaseUserMapping_333}{email}'),
                ('$cuids->{BaseUserMapping_666}', 0, '$bu->{BaseUserMapping_666}{login}', '$bu->{BaseUserMapping_666}{wikiname}', 'Guest User', ''),
                ('$cuids->{BaseUserMapping_999}', 0, '$bu->{BaseUserMapping_999}{login}', '$bu->{BaseUserMapping_999}{wikiname}', 'Unknown User', '')"
    ]
);

sub new {
    my ($class, $session, $id, $config) = @_;
    my $this = $class->SUPER::new($session, $id, $config);
    return $this;
}

sub initiateLogin {
    my ($this, $origin) = @_;

    my $state = $this->SUPER::initiateLogin($origin);

    # my $auth = $this->_makeOAuth;
    # my $uri = $auth->authorize(
    #     redirect_uri => $this->processUrl(),
    #     scope => 'openid email profile',
    #     state => $state,
    #     hd => $this->{config}{domain},
    # );

    # my $session = $this->{session};
    # $this->{session}{response}->redirect(
    #     -url     => $uri,
    #     -cookies => $session->{response}->cookies(),
    #     -status  => '302',
    # );
    return 1;
}

sub isMyLogin {
    my $this = shift;
    my $req = $this->{session}{request};
    return $req->param('state') && $req->param('code');
}

sub processLogin {
    my $this = shift;
    my $req = $this->{session}{request};
    my $state = $req->param('state');
    $req->delete('state');
    die with Error::Simple("You seem to be using an outdated URL. Please try again.\n") unless $this->SUPER::processLogin($state);

    my $uauth = Foswiki::UnifiedAuth->new();
    my $db = $uauth->db;
    $uauth->apply_schema('users_baseuser', @schema_updates);
    my $provider = $db->selectrow_hashref("SELECT * FROM providers WHERE name=?", {}, $this->{id});

    return {};
}

1;
