package Foswiki::UnifiedAuth::Providers::Google;

use Error;
use JSON;
use LWP::UserAgent;
use Net::OAuth2::Profile::WebServer;

use strict;
use warnings;

use Foswiki::Func;
use Foswiki::Plugins::UnifiedAuthPlugin;
use Foswiki::UnifiedAuth;
use Foswiki::UnifiedAuth::Provider;
our @ISA = qw(Foswiki::UnifiedAuth::Provider);

my @schema_updates = (
    [
        "CREATE TABLE IF NOT EXISTS users_google (
            cuid UUID NOT NULL,
            pid INTEGER NOT NULL,
            info JSONB NOT NULL,
            PRIMARY KEY (cuid)
        )",
        "INSERT INTO meta (type, version) VALUES('users_google', 0)"
    ]
);

sub new {
    my ($class, $session, $id, $config) = @_;

    my $this = $class->SUPER::new($session, $id, $config);

    return $this;
}

sub forceButton {
    my ($this) = @_;

    return undef if defined $this->{config}->{forcable} && !$this->{config}->{forcable};

    my $icon;
    if($this->{config}->{loginIcon}){
        $icon = $this->{config}->{loginIcon};
    } else {
        $icon = $Foswiki::cfg{PubUrlPath}.'/'.$Foswiki::cfg{SystemWebName}.'/UnifiedAuthContrib/logo_google.svg';
    }
    my $description;
    if($this->{config}->{loginDescription}){
        $description = $this->{config}->{loginIcon};
    } else {
        $description = 'Login with Google';
    }
    return ($icon, $description);
}

sub _makeOAuth {
    my $this = shift;
    my $ua = LWP::UserAgent->new;
    my $res = $ua->get("https://accounts.google.com/.well-known/openid-configuration");
    die "Error retrieving Google authentication metadata: ".$res->as_string unless $res->is_success;
    my $json = decode_json($res->decoded_content);
    $this->{oid_cfg} = $json;
    Net::OAuth2::Profile::WebServer->new(
        client_id => $this->{config}{client_id},
        client_secret => $this->{config}{client_secret},
        site => '',
        secrets_in_params => 0,
        authorize_url => $json->{authorization_endpoint},
        access_token_url => $json->{token_endpoint},
    );
}

sub initiateExternalLogin {
    my $this = shift;
    my $state = shift;

    my $session = $this->{session};

    my $auth = $this->_makeOAuth;
    my $uri = $auth->authorize(
        redirect_uri => $this->processUrl('google_login' => 1),
        scope => 'openid email profile',
        state => $state,
        hd => $this->{config}{domain},
    );

    $this->{session}{response}->redirect(
        -url     => $uri,
        -cookies => $session->{response}->cookies(),
        -status  => '302',
    );
    return 1;
}

sub initiateLogin {
    my ($this, $state, $forced) = @_;

    my $cgis = $this->{session}->getCGISession;

    unless($forced) {
        return 0 unless $this->{config}->{autoLogin};
        return 0 if $cgis->param("uauth_$this->{id}_logged_out");
        return 0 if $cgis->param("uauth_$this->{id}_attempted");
    } else {
        $cgis->clear("uauth_$this->{id}_logged_out", "uauth_$this->{id}_attempted");
    }

    return $this->initiateExternalLogin($state);
}

sub isEarlyLogin {
    return 1;
}

sub isMyLogin {
    my $this = shift;
    my $req = $this->{session}{request};
    return $req->param('google_login');
}

sub processLogin {
    my $this = shift;
    my $req = $this->{session}{request};
    my $state = $req->param('state');
    $req->delete('session_state');
    $req->delete('authuser');
    $req->delete('hd');
    $req->delete('prompt');
    $req->delete('state');

    my $auth = $this->_makeOAuth;
    my $token = $auth->get_access_token($req->param('code'),
        redirect_uri => $this->processUrl('google_login' => 1),
    );
    $req->delete('code');
    if ($token->error) {
        throw Error::Simple("Login failed: ". $token->error_description ."\n");
    }
    my $tokenType = $token->token_type;
    $token = $token->access_token;
    my $ua = LWP::UserAgent->new;
    my $acc_info = $ua->simple_request(HTTP::Request->new('GET', $this->{oid_cfg}{userinfo_endpoint},
        ['Authorization', "$tokenType $token"]
    ));
    unless ($acc_info->is_success) {
        throw Error::Simple("Failed to get user information from Google: ". $acc_info->as_string ."\n");
    }

    $acc_info = decode_json($acc_info->decoded_content);
    my $enforceDomain = $this->{config}{enforceDomain} || 0;
    if ($this->{config}{domain} && $enforceDomain) {
        my $extra = $this->{config}{extraDomains} || [];
        $extra = ref($extra) eq 'ARRAY' ? $extra : [$extra];
        unless ($acc_info->{hd} && $acc_info->{hd} eq $this->{config}{domain}) {
          unless ($acc_info->{hd} && grep(/$acc_info->{hd}/, @$extra)) {
            throw Error::Simple("\%BR\%You're *not allowed* to access this site.");
          }
        }
    }

    my $user_email = $acc_info->{email};

    if ( $this->{config}{identityProvider} ) {
        my $user_id = $user_email;
        $user_id =~ s/\@.*// unless $this->{config}->{identifyWithRealm};
        return { identity => $user_id };
    }

    # email, name, family_name, given_name
    my $uauth = Foswiki::UnifiedAuth->new();
    my $db = $uauth->db;
    my $pid = $this->getPid();
    $uauth->apply_schema('users_google', @schema_updates);
    my $exist = $uauth->getCUIDByLoginAndPid($acc_info->{email}, $pid);
    unless ($exist) {
        my $user_id;
        eval {
            $db->begin_work;
            $user_id = $uauth->add_user('UTF-8', $pid, {
                email => $user_email,
                login_name => $user_email,
                wiki_name => $this->_formatWikiName($acc_info),
                display_name => $this->_formatDisplayName($acc_info)
            });
            $db->do("INSERT INTO users_google (cuid, pid, info) VALUES(?,?,?)", {}, $user_id, $pid,JSON::encode_json($acc_info));
            $db->commit;
        };
        if ($@) {
            my $err = $@;
            eval { $db->rollback; };
            throw Error::Simple("Failed to initialize Google account '$user_email' ($err)\n");
        }

        return {
            cuid => $user_id,
            data => $acc_info,
        };
    }

    # Check if values need updating
    my $userdata = $db->selectrow_hashref("SELECT * FROM users AS u NATURAL JOIN users_google WHERE u.login_name=? AND u.pid=?", {}, $acc_info->{email}, $pid);
    my $cur_dn = $this->_formatDisplayName($acc_info);
    if ($cur_dn ne $userdata->{display_name}) {
        $uauth->update_user('UTF-8', $userdata->{cuid}, {email => $acc_info->{email}, display_name => $cur_dn});
    }

    return $userdata->{login_name} if $this->{config}{identityProvider};
    return {
        cuid => $userdata->{cuid},
        data => $acc_info,
    };
}

sub _formatWikiName {
    my ($this, $data) = @_;
    my $format = $this->{config}{wikiname_format} || '$name';
    _applyFormat($format, $data);
}

sub _formatDisplayName {
    my ($this, $data) = @_;
    my $format = $this->{config}{displayname_format} || '$name';
    _applyFormat($format, $data);
}

sub _applyFormat {
    my ($format, $data) = @_;
    for my $k (keys %$data) {
        $format =~ s/\$$k\b/$data->{$k}/g;
    }
    return $format;
}

1;
