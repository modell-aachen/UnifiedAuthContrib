# See bottom of file for license and copyright information

=begin TML

---+ package Foswiki::LoginManager::UnifiedLogin

=cut

package Foswiki::LoginManager::UnifiedLogin;

use strict;
use warnings;
use Assert;

use JSON;
use Unicode::Normalize;
use Error ':try';
use Error::Simple;
use Digest::SHA qw(sha1_base64);

use Foswiki::LoginManager ();
use Foswiki::Users::BaseUserMapping;
use Foswiki::UnifiedAuth::Providers::BaseUser;

our @ISA = ('Foswiki::LoginManager');

sub new {
    my ( $class, $session ) = @_;
    my $this = $class->SUPER::new($session);
    $session->enterContext('can_login');
    if ( $Foswiki::cfg{Sessions}{ExpireCookiesAfter} ) {
        $session->enterContext('can_remember_login');
    }

    # re-registering these, so we use our own methods.
    Foswiki::registerTagHandler( 'LOGOUT',           \&_LOGOUT );
    Foswiki::registerTagHandler( 'LOGOUTURL',        \&_LOGOUTURL );

    return $this;
}

sub finish {
    my $this = shift;

    eval {
        $this->complete();
    };
    if ($@) {
        print STDERR "Error while completing LoginManager: $@\nIgnoring!\n";
        if ($Foswiki::cfg{Sessions}{ExpireAfter} > 0) {
            Foswiki::LoginManager::expireDeadSessions();
        }
    }

    undef $this->{_authScripts};
    undef $this->{_cgisession};
    undef $this->{_haveCookie};
    undef $this->{_MYSCRIPTURL};
    undef $this->{session};

    undef $this->{uac};
    undef $this->{tmpls};
}

# Stores important request parameters in the session and returns a key to
# access them.
# The parameters can be retrieved with _stateToRequest.
# Only return the key, to prevent information disclosure or the possibility to
# forge and inject a request.
sub _requestToState {
    my ( $this ) = @_;

    my $cgis = $this->{session}->getCGISession();
    die with Error::Simple("Login requires a valid session; do you have cookies disabled?") if !$cgis;

    my $request = $this->{session}->{request};
    my $uri = $request->uri();
    my $method = $request->method() || 'UNDEFINED';
    my $action = $request->action();

    my $origin = "$method,$action,$uri";

    my $states = $cgis->param('uauth_state') || {};
    eval {
        while (my ($oldState, $oldValue) = each (%$states)) {
            if($oldValue eq $origin) {
                return $oldState;
            }
        }
    };
    if($@) {
        Foswiki::Func::writeWarning("Could not read old states, resetting to blank");
        $states = {};
    }

    my $state = sha1_base64(rand(). "$$ $0");
    $state =~ tr#+/=#-_~#; # make it url-friendly, so providers do not need to encode this
    $states->{$state} = $origin;
    $cgis->param('uauth_state', $states);

    $cgis->flush;
    die $cgis->errstr if $cgis->errstr;

    return $state;
}

# Returns the method, action and uri that are associated with the state, so the
# request can be restored.
sub _stateToRequest {
    my ($this, $state) = @_;
    return unless $state;

    my $cgis = $this->{session}->getCGISession();
    die with Error::Simple("Login requires a valid session; do you have cookies disabled?") if !$cgis;

    my $saved = $cgis->param('uauth_state') || {};
    my $savedValue = $saved->{$state};
    unless($savedValue) {
        Foswiki::Func::writeWarning("Could not find state in cgi session");
        return 0;
    }

    my ( $method, $action, $uri ) = split( ',', $savedValue, 3 );
    return ( Foswiki::urlDecode($uri), $method, $action );
}

sub _authProvider {
    my ($this, $provider) = @_;

    $this->{uac} = Foswiki::UnifiedAuth->new unless $this->{uac};
    $this->{uac}->authProvider($this->{session}, $provider);
}

sub forceAuthentication {
    my $this    = shift;
    my $session = $this->{session};

    unless ( $session->inContext('authenticated') ) {
        my $query    = $session->{request};
        my $response = $session->{response};
        my $state = $this->_requestToState();

        my $authid = $Foswiki::cfg{UnifiedAuth}{DefaultAuthProvider};
        if ($authid) {
            my $provider = $this->_authProvider($authid);
            if ($provider->enabled && !$provider->useDefaultLogin) {
                return $this->_initiateProviderLogin($provider, $state);
            }
        }

        # Respond with a 401 with an appropriate WWW-Authenticate
        # that won't be snatched by the browser, but can be used
        # by JS to generate login info.
        $response->header(
            -status           => 200,
            -WWW_Authenticate => 'FoswikiBasic realm="'
              . ( $Foswiki::cfg{AuthRealm} || "" ) . '"'
        );

        $query->param(
            -name  => 'foswiki_origin',
            -value => $state,
        );

        # Throw back the login page with the 401
        $this->login( $query, $session );
        return 1;
    }

    return 0;
}

sub loginUrl {
    my $this    = shift;
    my $session = $this->{session};
    my $topic   = $session->{topicName};
    my $web     = $session->{webName};
    return $session->getScriptUrl( 0, 'login', $web, $topic,
        foswiki_origin => $this->_requestToState() );
}

sub _loadTemplate {
    my $this = shift;
    my $tmpls = $this->{session}->templates;
    $this->{tmpls} = $tmpls;
    return $tmpls->readTemplate('uauth');
}

=begin TML

---++ ObjectMethod login( $query, $session )

If a login name and password have been passed in the query, it
validates these and if authentic, redirects to the original
script. If there is no username in the query or the username/password is
invalid (validate returns non-zero) then it prompts again.

If a flag to remember the login has been passed in the query, then the
corresponding session variable will be set. This will result in the
login cookie being preserved across browser sessions.

The password handler is expected to return a perl true value if the password
is valid. This return value is stored in a session variable called
VALIDATION. This is so that password handlers can return extra information
about the user, such as a list of Wiki groups stored in a separate
database, that can then be displayed by referring to
%<nop>SESSION_VARIABLE{"VALIDATION"}%

=cut

sub login {
    my ( $this, $query, $session ) = @_;

    my $providers = $this->_getProviders();

    my $forcedProvider = $query->param('uauth_force_provider');

    my $result = $this->_checkProvidersForLoginAttempt($query, $session, $providers, $forcedProvider);
    return $result if $result;

    return $this->_initiateLogin($query, $session, $providers, $forcedProvider);
}

sub _initiateProviderLogin {
    my ($this, $provider, $state, $providers, $force) = @_;

    my $result = $provider->initiateLogin($state, $force);
    if($result == $Foswiki::UnifiedAuth::Provider::INITIATE_LOGIN_RENDERDEFAULT) {
        $this->_initiateDefaultLogin($state, $providers);
    }
    return $result;
}

sub _initiateDefaultLogin {
    my ($this, $state, $providers) = @_;

    $providers ||= $this->_getProviders();

    return $this->_authProvider('__default')->initiateLogin($state, 0, $providers);
}

sub _initiateLogin {
    my ( $this, $query, $session, $providers, $forcedProvider ) = @_;

    my $state = $this->_requestToState();

    $query->delete('validation_key');
    if ($forcedProvider) {
        if($forcedProvider eq '__default') {
            return $this->_initiateDefaultLogin($state, $providers);
        }

        if (!exists $Foswiki::cfg{UnifiedAuth}{Providers}{$forcedProvider}) {
            die "Invalid authentication source requested";
        }
        my $forcedState = $query->param('state') || $state;
        my $provider = $this->_authProvider($forcedProvider);
        return $this->_initiateProviderLogin($provider, $forcedState, $providers, 1);
    }

    foreach my $provider (@$providers) {
        next if $provider->useDefaultLogin();
        my $initLogin = $this->_initiateProviderLogin($provider, $state, $providers);
        return $initLogin if $initLogin;
    }

    if (my $authid = $Foswiki::cfg{UnifiedAuth}{DefaultAuthProvider}) {
        my $provider = $this->_authProvider($authid);

        return $this->_initiateProviderLogin($provider, $state) unless $provider->useDefaultLogin();
    }

    return $this->_initiateDefaultLogin($state, $providers);
}

sub _checkProvidersForLoginAttempt {
    my ($this, $query, $session, $providers, $forcedProvider) = @_;

    my $errors = [];
    my $result;
    foreach my $provider (@$providers) {
        next if $forcedProvider && $forcedProvider ne $provider->{id};
        eval {
            if ($provider->isMyLogin($forcedProvider)) {
                $result = $this->processProviderLogin($query, $session, $provider, $errors);
            }
        };
        if($@) {
            if (ref($@) && $@->isa("Error")) {
                push @$errors, $@->text;
            } else {
                push @$errors, $@;
            }
        }
        last if defined $result && $result ne '';
    }

    if(@$errors) {
        my $tmpl = $this->_loadTemplate;
        my $banner = '';
        $banner = $this->{tmpls}->expandTemplate('AUTH_FAILURE');

        $session->{prefs}->setSessionPreferences(UAUTH_AUTH_FAILURE_MESSAGE => join('<br/>', @$errors), BANNER => $banner);
    }

    return $result;
}

sub _getProviders {
    my ( $this ) = @_;

    my @providers = sort keys %{$Foswiki::cfg{UnifiedAuth}{Providers}};
    push @providers, '__baseuser';
    push @providers, '__default';
    @providers = map {$this->_authProvider($_)} @providers;

    my @sortedProviders = ();
    foreach my $provider (@providers) {
        next unless $provider->enabled();
        if($provider->isEarlyLogin()) {
            unshift @sortedProviders, $provider; # XXX reverses order of early providers
        } else {
            push @sortedProviders, $provider;
        }
    }

    return (\@sortedProviders);
}


sub loadSession {
    my $this = shift;

    my $session = $this->{session};
    my $req = $session->{request};
    my $logout = $session && $req && $req->param('logout');
    my $user = $this->SUPER::loadSession(@_);
    my $cgis = $session->getCGISession(); # note: might not exist (eg. call from cli)

    my $bu = \%Foswiki::Users::BaseUserMapping::BASE_USERS;
    my $cuids = \%Foswiki::UnifiedAuth::Providers::BaseUser::CUIDs;
    foreach my $base (keys %$bu) {
        my $login = $bu->{$base}{login};
        my $wn = $bu->{$base}{wikiname};
        $session->{users}->{login2cUID}->{$login} = $cuids->{$base};
        $session->{users}->{wikiName2cUID}->{$wn} = $cuids->{$base};
    }

    if ($logout) {
        if ($cgis) {
            $cgis->clear(['uauth_state']);
        }

        while (my ($id, $hash) = each %{$Foswiki::cfg{UnifiedAuth}{Providers}}) {
            my $mod = $hash->{module};
            next unless $mod;
            my $provider = $this->_authProvider($id);
            if($provider->can('handleLogout')) {
                $provider->handleLogout($session, $user);
            }
        }
    }

    if(Foswiki::Func::isAnAdmin($user) && (my $refresh = $req->param('refreshauth'))) {
        $req->delete('refreshauth');
        if($refresh eq 'all') {
            Foswiki::Func::writeWarning("refreshing all providers");
            foreach my $id ( ('__baseuser', sort(keys %{$Foswiki::cfg{UnifiedAuth}{Providers}}), '__uauth' ) ) {
                Foswiki::Func::writeWarning("refreshing $id");
                try {
                    my $provider = $this->_authProvider($id);
                    $provider->refresh() if $provider;
                } catch Error::Simple with {
                    Foswiki::Func::writeWarning(shift);
                };
            }
        } elsif ((defined $Foswiki::cfg{UnifiedAuth}{Providers}{$refresh}) || $refresh eq '__uauth') {
            my $provider = $this->_authProvider($refresh);
            $provider->refresh() if $provider;
        }
        # dump the db for backup solutions
        unless ( $Foswiki::cfg{UnifiedAuth}{NoDump} ) {
            my $dumpcmd = $Foswiki::cfg{UnifiedAuth}{DumpCommand} || 'pg_dump foswiki_users';
            my ($output, $exit, $stderr) = Foswiki::Sandbox->sysCommand(
                $dumpcmd
            );
            if($exit) {
                $stderr = '' unless defined $stderr;
                Foswiki::Func::writeWarning("Error while dumping foswiki_users: $exit\n$output\n$stderr");
            } else {
                my $dir = Foswiki::Func::getWorkArea('UnifiedAuth');
                Foswiki::Func::saveFile("$dir/foswiki_users.dump", $output);
            }
        }
    }

    if ($cgis && $cgis->param('force_set_pw') && $req) {
        my $topic  = $session->{topicName};
        my $web    = $session->{webName};
        unless( $req->param('resetpw')) {
            unless( $topic eq $Foswiki::cfg{HomeTopicName} && $web eq $Foswiki::cfg{SystemWebName}) {
                my $url = Foswiki::Func::getScriptUrl($Foswiki::cfg{SystemWebName},
                               'ChangePassword',
                               'oops',
                               template => 'oopsresetpassword',
                               resetpw => '1');
                Foswiki::Func::redirectCgiQuery( undef, $url);
            }
        }
    }
    return $user;
}

sub processProviderLogin {
    my ($this, $query, $session, $provider, $errors) = @_;

    my $context = Foswiki::Func::getContext();
    my $topic  = $session->{topicName};
    my $web    = $session->{webName};

    my $loginResult;
    eval {
        $loginResult = $provider->processLogin();
        if (!$loginResult) {
            # do nothing, login failed
        } elsif ($loginResult->{cuid}) {
            # do nothing, login success
        } elsif ($loginResult->{'wait for next step'}) {
            Foswiki::Func::writeWarning("Waiting for client to get back to us.") if defined $provider->{config}->{debug} && $provider->{config}->{debug} eq 'verbose';
            undef $loginResult;
        } elsif ($loginResult->{identity} && $provider->{config}->{identityProvider}) {
            my $providerConfig = $provider->{config}->{identityProvider};
            my @providers;
            if($providerConfig eq '_all_') {
                # Note: we can not simply search the users table for the login
                # since it can be rewritten by the providers (eg. lowercased)
                #
                # Sorting the providers, so we get a consistent result, should
                # a login appear twice (misconfiguration)
                @providers = sort keys %{$Foswiki::cfg{UnifiedAuth}{Providers}};
            } else {
                @providers = split(/\s*,\s*/, $providerConfig);
            }
            my $providersResult;
            foreach my $providerName ( @providers ) {
                my $provider = $this->_authProvider($providerName);
                if ($provider->isa('Foswiki::UnifiedAuth::IdentityProvider')) {
                    $providersResult = $provider->identify($loginResult->{identity});
                    last if $providersResult;
                }
            }
            if($providersResult) {
                $loginResult = {%$loginResult, %$providersResult};
            } else {
                if($provider->{config}->{debug}) {
                    Foswiki::Func::writeWarning("Login '$loginResult->{identity}' supplied by '$provider->{id}' could not be found in identity provider '$provider->{config}->{identityProvider}'"); # do not use $id_provider, because it might have been _all_
                }
                push @$errors, $session->i18n->maketext("Your user account is not configured for the authentication with this wiki. Please contact your administrator for further assistance.");
                undef $loginResult;
            }
        }
    };
    if ($@) {
        if (ref($@) && $@->isa("Error")) {
            push @$errors, $@->text;
        } else {
            Foswiki::Func::writeWarning($@);
        }
    }

    if ($loginResult && $loginResult->{cuid}) {
        # NOTE: This is just a safety net, each provider MUST check if the
        # login is active or not. Otherwise a deactivated provider will also
        # invalidate following providers.
        my ($deactivated, $uac_disabled) = $this->{uac}->{db}->selectrow_array("SELECT deactivated, uac_disabled FROM users WHERE cuid=?", {}, $loginResult->{cuid});

        unless ($deactivated || $uac_disabled) {
            $this->userLoggedIn($loginResult->{cuid});
            $session->logger->log(
                {
                    level    => 'info',
                    action   => 'login',
                    webTopic => $web . '.' . $topic,
                    extra    => "AUTHENTICATION SUCCESS - $loginResult->{cuid} - "
                }
            );
            $this->{_cgisession}->param( 'VALIDATION', encode_json($loginResult->{data} || {}) )
              if $this->{_cgisession};

            $this->_setRedirect($session, $query, $loginResult);

            return $loginResult->{cuid};
        }
    }

    if ($Foswiki::cfg{UnifiedAuth}{DefaultAuthProvider}) {
        $context->{uauth_failed_nochoose} = 1;
    }

    $session->logger->log(
        {
            level    => 'info',
            action   => 'login',
            webTopic => $web . '.' . $topic,
            extra    => "AUTHENTICATION FAILURE",
        }
    );

    return undef;
}

sub _setRedirect {
    my ($this, $session, $query, $loginResult) = @_;

    if($loginResult->{state}){
        $this->_redirectFromState($loginResult->{state}, $session);
    } else {
        $session->redirect($query->{uri}, 1);
    }

    if($this->_isLoginAction($session->{request})) {
        $this->_redirectFromLoginAction($session); #Breaks an infinite login loop
    }
}

sub _isLoginAction {
    my (undef, $request) = @_;
    return $request->action() =~ m/^log[io]n$/;
}

sub _redirectFromState {
    my ($this, $state, $session) = @_;

    my ( $origurl, $origmethod, $origaction ) = $this->_stateToRequest($state);

    # Restore url
    if ( $origurl =~ s/\?([^#]*)// ) {
        foreach my $pair ( split( /[&;]/, $1 ) ) {
            if ( $pair =~ /(.*?)=(.*)/ ) {
                $session->{request}->param( $1, TAINT($2) );
            }
        }
    }

    $session->{request}->method($origmethod);
    $session->{request}->action($origaction);
    $session->redirect($origurl, 1);
}

sub _redirectFromLoginAction {
    my ($this, $session) = @_;
    my $topic  = $session->{topicName};
    my $web    = $session->{webName};
    $session->{request}->method('get');
    $session->{request}->action('view');
    $session->{request}->delete_all;

    $session->redirect($session->getScriptUrl(0, 'view', $web, $topic), 1);
}

# Like the super method, but checks if the topic exists (to avoid dead links).
sub _LOGOUTURL {
    my ( $session, $params, $topic, $web ) = @_;
    my $this = $session->getLoginManager();

    my $logoutWeb = $session->{prefs}->getPreference('BASEWEB');
    my $logoutTopic = $session->{prefs}->getPreference('BASETOPIC');
    unless(Foswiki::Func::topicExists($logoutWeb, $logoutTopic)) {
        $logoutWeb = $Foswiki::cfg{UsersWebName};
        $logoutTopic = $Foswiki::cfg{HomeTopicName};
    }

    return $session->getScriptUrl(
        0, 'view',
        $logoutWeb,
        $logoutTopic,
        'logout' => 1
    );
}

# Unmodified from super method, however we need to copy it, so we can use the
# modified _LOGOUTURL.
sub _LOGOUT {
    my ( $session, $params, $topic, $web ) = @_;
    my $this = $session->getLoginManager();

    return '' unless $session->inContext('authenticated');

    my $url = _LOGOUTURL(@_);
    if ($url) {
        my $text = $session->templates->expandTemplate('LOG_OUT');
        return CGI::a( { href => $url }, $text );
    }
    return '';
}

1;
__END__
Module of Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2008-2014 Foswiki Contributors. All Rights Reserved.
Foswiki Contributors are listed in the AUTHORS file in the root
of this distribution. NOTE: Please extend that file, not this notice.

Additional copyrights apply to some or all of the code in this
file as follows:

Copyright (C) 2005-2006 TWiki Contributors. All Rights Reserved.
Copyright (C) 2005 Greg Abbas, twiki@abbas.org

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
