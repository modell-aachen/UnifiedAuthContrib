# See bottom of file for license and copyright information

package Foswiki::Plugins::UnifiedAuthPlugin;

use strict;
use warnings;

use Foswiki::Func;
use Foswiki::Prefs;
use Foswiki::Contrib::PostgreContrib;
use Foswiki::UnifiedAuth;
use Foswiki::Contrib::MailTemplatesContrib;
use JSON;

require Foswiki::Users;

our $VERSION = '1.0';
our $RELEASE = "1.0";
our $SHORTDESCRIPTION = 'Handlers for UnifiedAuthContrib';

our $connection;

sub initPlugin {
    Foswiki::Func::registerTagHandler('AUTHPROVIDERS',\&_AUTHPROVIDERS);
    Foswiki::Func::registerTagHandler('TOTALUSERS', \&_TOTALUSERS);
    Foswiki::Func::registerTagHandler('SHOWRESETPASSWORD', \&_SHOWRESETPASSWORD);

    Foswiki::Func::registerRESTHandler( 'registerUser',
        # \&_registerUser,
        \&_bad_request,
        authenticate => 0,
        validate => 0,
        http_allow => 'POST',
    );

    Foswiki::Func::registerRESTHandler( 'users',
        # \&_RESTusers,
        \&_bad_request,
        authenticate => 1,
        validate => 0,
        http_allow => 'GET',
    );

    Foswiki::Func::registerRESTHandler( 'addUsersToGroup',
        # \&_addUsersToGroup,
        \&_bad_request,
        authenticate => 1,
        validate => 0,
        http_allow => 'POST',
    );
    Foswiki::Func::registerRESTHandler( 'removeUserFromGroup',
        # \&_removeUserFromGroup,
        \&_bad_request,
        authenticate => 1,
        validate => 0,
        http_allow => 'POST',
    );
    Foswiki::Func::registerRESTHandler( 'resetPassword',
        # \&_resetPassword,
        \&_bad_request,
        authenticate => 1,
        validate => 0,
        http_allow => 'POST',
    );
    Foswiki::Func::registerRESTHandler( 'setPassword',
        # \&_setPassword,
        \&_bad_request,
        authenticate => 0,
        validate => 0,
        http_allow => 'GET,POST',
    );
    Foswiki::Func::registerRESTHandler( 'updateEmail',
        # \&_updateEmail,
        \&_bad_request,
        authenticate => 1,
        validate => 0,
        http_allow => 'POST',
    );
    Foswiki::Func::registerRESTHandler( 'toggleUserState',
        # \&_toggleUserState,
        \&_bad_request,
        authenticate => 1,
        validate => 0,
        http_allow => 'POST',
    );
    return 1;
}

sub _bad_request {
    my ($session, $subject, $verb, $response) = @_;
    $response->header(-status => 400);
    return to_json({status => 'error', msg => 'Bad request'});
}

sub _AUTHPROVIDERS {
    my ( $session, $attrs, $topic, $web ) = @_;

    my $providers = $Foswiki::cfg{UnifiedAuth}{Providers};
    return '' unless defined $providers;

    my $choose = 0;
    my $ctx = Foswiki::Func::getContext();
    my $auth = Foswiki::UnifiedAuth->new();

    while (my ($id, $hash) = each %$providers) {
        next unless $hash->{module} =~ /Google|Facebook|Steam/;
        my $provider = $auth->authProvider($session, $id);
        next unless $provider->enabled;
        $ctx->{'UA_'.uc($id)} = 1;
        $ctx->{'UA_CHOOSE'} = 1;
    }

    my $path = '%PUBURLPATH%/%SYSTEMWEB%/UnifiedAuthContrib';
    Foswiki::Func::addToZone(
        'head',
        'uauth:css',
        "<link rel=\"stylesheet\" type=\"text/css\" media=\"all\" href=\"$path/css/uauth.css?version=$RELEASE\" />"
    );

    if ($ctx->{'UA_CHOOSE'}) {
        Foswiki::Func::addToZone(
            'script',
            'uauth:js',
            "<script type=\"text/javascript\" src=\"$path/js/uauth.js?version=$RELEASE\"></script>",
            'JQUERYPLUGIN::FOSWIKI::PREFERENCES'
        );
    }

    return '';
}

sub _TOTALUSERS {
    my($session, $params, $topic, $web, $topicObject) = @_;
    my $db = _getConnection();
    my $exclude = $params->{_DEFAULT} || $params->{exclude_deactivated};
    my $baseQuery = "SELECT COUNT(DISTINCT users.cuid) FROM users INNER JOIN providers ON (users.pid=providers.pid) WHERE NOT providers.name ~ '^__'";
    return $db->selectrow_array($baseQuery, {}) unless Foswiki::isTrue($exclude, 0);
    $db->selectrow_array("$baseQuery AND users.deactivated=0", {});
}

sub _SHOWRESETPASSWORD {
    my($session, $params, $topic, $web, $topicObject) = @_;
    my $showResetPassword = $Foswiki::cfg{UnifiedAuth}{ShowResetPassword} || 0;
    return $showResetPassword;
}

sub _registerUser {
    my ($session, $subject, $verb, $response) = @_;
    my $q = $session->{request};
    my $auth = Foswiki::UnifiedAuth->new();

    my $loginName = $q->param("loginName");
    my $wikiName = $q->param("wikiName");
    my $password = $q->param("password");
    my $email = $q->param("email");

    unless ($loginName and $wikiName and $email){
        $response->header(-status => 400);
        return to_json({status => 'error', msg => "Missing mandatory parameters"});
    }

    unless($password){
        $password = Foswiki::Users::randomPassword();
    }

    my %providers = %{$Foswiki::cfg{UnifiedAuth}{Providers}};
    my $topicProvider;
    while (my ($id, $hash) = each %providers) {
        next unless $hash->{module} =~ /^Topic$/;
        $topicProvider = $auth->authProvider($session, $id);
        last;
    }

    unless($topicProvider){
        $response->header(-status => 500);
        return to_json({status => 'error', msg => "User provider (TOPIC) not configured"});
    }

    unless($topicProvider->enabled){
        $response->header(-status => 500);
        return to_json({status => 'error', msg => "User provider (TOPIC) disabled"});
    }

    my $cuid;
    eval {
        $cuid = $topicProvider->addUser($loginName, $wikiName, $password, $email);
    };

    if($@){
        my $err = $@;
        Foswiki::Func::writeWarning($err);
        $response->header(-status => 400);
        my $msg = "Failure while creating user";
        $msg = "User already exists" if $err =~ /already in use/;
        return to_json({status => 'error', msg => $msg});
    }

    my $mailPreferences = {
        REGISTRATION_MAIL => $email,
        REGISTRATION_WIKINAME => $wikiName,
        REGISTRATION_PASSWORD => $password
    };

    Foswiki::Contrib::MailTemplatesContrib::sendMail("uauth_registernotify", {GenerateInAdvance => 1}, $mailPreferences, 1);
    $topicProvider->indexUser($cuid);

    return to_json({status => "ok"});
}

sub _RESTusers {
    my ($session, $subject, $verb, $response) = @_;
    my $q = $session->{request};
    my $searchParam = $q->param("q") || '';
    my $limit = $q->param("limit") || 10;
    my $page = $q->param("page") / $limit || 0;
    my @field = split(/\s*,\s*/, Foswiki::Func::getPreferencesValue('QUERYUSERS_DEFAULT_FIELDS'));
    my $basemapping = $q->param("basemapping") || "skip";
    my $type;
    if($q->param("user") && $q->param("group")){
        $type = "any";
    }elsif($q->param("group")){
        $type= "group";
    }else{
        $type="user";
    }
    my $auth = Foswiki::UnifiedAuth->new();
    my ($result, $count) = $auth->queryUser({
            term => $searchParam,
            limit => $limit,
            page => $page,
            type => $type,
            searchable_fields => \@field,
            basemapping => $basemapping
        });
    for my $entry (@{$result}){
        $entry->{'name'} = $entry->{'displayname'} || $entry->{'wikiname'};
        $entry->{'id'} = $entry->{'cuid'} ;
    }
    return to_json($result);
}

sub _addUsersToGroup {
    my ($session, $subject, $verb, $response) = @_;
    my $q = $session->{request};
    my $auth = Foswiki::UnifiedAuth->new();

    my $params;
    eval {
        $params = from_json($q->param("params"));
    };
    if($@){
        $response->header(-status => 404);
        Foswiki::Func::writeWarning($@);
        return to_json({status => 'error', msg => "Error - pleas ask your admin"});
    }
    my $group = $params->{group}->{name};
    my @cuids;
    my $create = $params->{create};
    if(ref($params->{cuids}) eq "ARRAY"){
        @cuids = @{$params->{cuids}};
    }else{
        push @cuids, $params->{cuids} if $params->{cuids};
    }
    if($params->{cuid}){
        push @cuids, {name => $params->{wikiName}, id => $params->{cuid}};
    }
    unless ($group){
        $response->header(-status => 400);
        return to_json({status=> 'error', msg => "Missing params"});
    }

    unless ($create){
        $create = 0;
    }
    #Create empty Group
    if (scalar @cuids == 0 && $create) {
        my $userMapping = Foswiki::Users::UnifiedUserMapping->new($session);
        $userMapping->addUserToGroup(undef, $group, $create);
    }
    foreach my $cuid (@cuids) {
        eval {
            my $userMapping = Foswiki::Users::UnifiedUserMapping->new($session);
            $userMapping->addUserToGroup($cuid->{id}, $group, $create);
            if(!$userMapping->isGroup($cuid->{id})){
                my $wikiName = $userMapping->getWikiName($cuid->{id});
                my $indexProvider = $auth->authProvider($session, $auth->getProviderForUser($wikiName));
                $indexProvider->indexUser($cuid->{id});
            }
        };
        if($@){
            $response->header(-status => 404);
            Foswiki::Func::writeWarning($@);
            return to_json({status => 'error', msg => "User could not be added to group."});
        }
    }

    my $db = $auth->db;
    my $providerInfo = $db->selectrow_hashref("SELECT providers.name FROM groups, providers WHERE groups.name=? AND groups.pid = providers.pid", {}, $group);
    my $groupInfo = $db->selectrow_hashref("SELECT * FROM groups WHERE groups.name=?", {}, $group);
    my $indexProvider = $auth->authProvider($session, $providerInfo->{name});
    $indexProvider->indexGroup($groupInfo->{cuid});
    return to_json({status => "ok", data => $groupInfo});
}

sub _removeUserFromGroup {
    my ($session, $subject, $verb, $response) = @_;
    my $q = $session->{request};
    my $auth = Foswiki::UnifiedAuth->new();

    my $params;
    eval {
        $params = from_json($q->param("params"));
    };
    if($@){
        $response->header(-status => 404);
        Foswiki::Func::writeWarning($@);
        return to_json({status => 'error', msg => "Error - pleas ask your admin"});
    }
    my $group = $params->{group};
    #TODO: use more then one cuid
    my $cuids = $params->{cuids};
    #TODO: also need more then one wikiName
    my $wikiName = $params->{wikiName};

    unless ($group and $cuids){
        $response->header(-status => 400);
        return to_json({status=> 'error', msg => "Missing params"});
    }

    eval {
        my $userMapping = Foswiki::Users::UnifiedUserMapping->new($session);
        $userMapping->removeUserFromGroup($cuids, $group);
        my $indexProvider = $auth->authProvider($session, $auth->getProviderForUser($wikiName));
        $indexProvider->indexUser($cuids);
    };
    if($@){
        $response->header(-status => 500);
        Foswiki::Func::writeWarning($@);
        return to_json({status => 'error', msg => "User could not be removed from group."});
    }

    my $db = $auth->db;
    my $providerInfo = $db->selectrow_hashref("SELECT providers.name FROM groups, providers WHERE groups.name=? AND groups.pid = providers.pid", {}, $group);
    my $groupInfo = $db->selectrow_hashref("SELECT * FROM groups WHERE groups.name=?", {}, $group);
    my $indexProvider = $auth->authProvider($session, $providerInfo->{name});
    $indexProvider->indexGroup($groupInfo->{cuid});
    return to_json({status => "ok", data => $groupInfo});
}

# handler for setting the user password with link
sub _resetPassword {
  my ($session, $subject, $verb, $response) = @_;
  my $q = $session->{request};
  my $auth = Foswiki::UnifiedAuth->new();

  my $cuid = $q->param("cuid");
  my $wikiname = $q->param("wikiname");

  my $db = $auth->db;
  my $userinfo = $db->selectrow_hashref("SELECT cuid, email FROM users WHERE users.cuid=?", {}, $cuid);

  unless ($wikiname && $cuid) {
    $response->header(-status => 400);
    return to_json({status => 'error', msg => "Missing params"});
  }
  # check for TopicProvider
  my $indexProvider = $auth->authProvider($session, $auth->getProviderForUser($wikiname));
  unless ($indexProvider->{name} =~ /Topic/) {
    $response->header(-status => 400);
    return to_json({status => 'error', msg => "Function only supported for topic provider"});
  }

  my $resetid = $indexProvider->generateResetId();
  my $timestamp = time();
  my $duration = 24; # in hours

  my $prefs = Foswiki::Prefs->new($session);
  $prefs->loadSitePreferences();
  my $prefValue = $prefs->getPreference("PASSWORD_RESET_DURATION");
  $prefs->finish();

  $duration = $prefValue if $prefValue;
  my $resetLimit = $timestamp + ($duration*3600);

  $auth->update_reset_request('UTF-8', $cuid, $resetid, $resetLimit);

  my $email = $userinfo->{email};
  my $mailPreferences = {
    REGISTRATION_MAIL => $userinfo->{email},
    RESET_ID => $resetid,
    RESET_LIMIT => $duration
  };

  Foswiki::Contrib::MailTemplatesContrib::sendMail("uauth_resetnotify", {GenerateInAdvance => 1}, $mailPreferences, 1);

  return to_json({status => "ok"});
}


sub _setPassword {
  my ($session, $subject, $verb, $response) = @_;
  my $q = $session->{request};

  my $auth = Foswiki::UnifiedAuth->new();
  my $db = $auth->db;

  my $resetid = $q->param("resetid");

  unless($resetid){
    $response->header(-status => 500);
    return to_json({status => "error"});
  }

  my $resetinfo = $db->selectrow_hashref("SELECT cuid, reset_limit FROM users WHERE users.reset_id=?", {}, $resetid);
  unless($resetinfo){
    Foswiki::Func::writeWarning("db returned no info for resetid $resetid");
    $response->header(-status => 403);
    return to_json({status => "error"});
  }

  return to_json({status => "time limit exceeded"}) unless $resetinfo->{reset_limit}>time();

  my $username = $q->param("username");
  my $newPassword = $q->param("password");
  my $newPasswordA = $q->param("passwordA");

  unless( $newPassword && $newPasswordA && $newPassword eq $newPasswordA ){
    Foswiki::Func::writeWarning("Missmatch between passwords.");
    $username = undef;
    $response->header(-status => 500);
    $response->pushHeader("message", "Passwords don't match.");
    # return to_json({status => "error", msg => "Passwords don't match."});
  }

  unless ( $username && $newPassword ) {
    my $path = '%PUBURLPATH%/%SYSTEMWEB%/UnifiedAuthContrib';
    Foswiki::Func::addToZone(
      'head',
      'uauth:css',
      "<link rel=\"stylesheet\" type=\"text/css\" media=\"all\" href=\"$path/css/uauth.css?version=$RELEASE\" />"
    );

    my $tml = Foswiki::Func::loadTemplate( 'oopssetpassword' );
    $tml = Foswiki::Func::expandCommonVariables($tml);
    my $html = Foswiki::Func::renderText($tml);
    return $html;
  }

  # check for combination of manually given username and resetid
  $resetinfo = $db->selectrow_hashref("SELECT cuid, reset_limit FROM users WHERE users.reset_id=? AND (users.wiki_name=? OR users.login_name=?)", {}, $resetid, $username, $username);

  unless ( $resetinfo->{cuid} ){
    Foswiki::Func::writeWarning("No db entry for the combination of username $username and reset_id $resetid.");
    $response->header(-status => 403);
    return to_json({status => "denied"});
  }

  my %providers = %{$Foswiki::cfg{UnifiedAuth}{Providers}};
  my $topicProvider;
  while (my ($id, $hash) = each %providers) {
    next unless $hash->{module} =~ /^Topic$/;
    $topicProvider = $auth->authProvider($session, $id);
    last;
  }

  unless($topicProvider){
    $response->header(-status => 500);
    return to_json({status => 'error', msg => "User provider (TOPIC) not configured"});
  }

  unless($topicProvider->enabled){
    $response->header(-status => 500);
    return to_json({status => 'error', msg => "User provider (TOPIC) disabled"});
  }

  my $result;
  eval {
    $result = $topicProvider->setPassword($username, $newPassword, '1');
  };

  Foswiki::Func::redirectCgiQuery( undef, $Foswiki::cfg{DefaultUrlHost});
}


sub _updateEmail {
    my ($session, $subject, $verb, $response) = @_;
    my $q = $session->{request};
    my $auth = Foswiki::UnifiedAuth->new();

    my $cuid = $q->param("cuid");
    my $email = $q->param("email");

    unless ($email && $cuid) {
        $response->header(-status => 400);
        return to_json({status => 'error', msg => "Missing params"});
    }

    my $indexProvider = $auth->authProvider($session, $auth->getProviderForUser($cuid));
    unless ($indexProvider->{name} =~ /Topic/) {
        $response->header(-status => 400);
        return to_json({status => 'error', msg => "Function only supported for topic provider"});
    }

    $auth->update_user('UTF-8', $cuid, {
        email => $email
    });
    $indexProvider->indexUser($cuid);

    return to_json({status => "ok"});
}

sub _toggleUserState {
    my ($session, $subject, $verb, $response) = @_;
    my $q = $session->{request};

    my $cuid = $q->param("cuid");
    unless ($cuid) {
        $response->header(-status => 400);
        return to_json({status => 'error', msg => "Missing parameter cUID"});
    }

    my $auth = Foswiki::UnifiedAuth->new();
    my $db = $auth->db;

    my $user = $db->selectrow_hashref("SELECT * FROM users WHERE users.cuid=?", {}, $cuid);
    my $deactivated = $user->{deactivated} ? 0 : 1;
    $auth->update_user('UTF-8', $user->{cuid}, {
        deactivated => $deactivated
    });

    my $provider = $auth->authProvider($session, $auth->getProviderForUser($cuid));
    $provider->indexUser($cuid);

    Foswiki::Func::writeEvent(
        "ua",
        "User $cuid " . ($deactivated ? 'deactivated' : 'activated')
    );

    return to_json({
        status => "ok",
        deactivated => $deactivated ? JSON::true : JSON::false
    });
}

sub finishPlugin {
    $connection->finish if $connection;
}

sub _getConnection {
    return $connection if $connection && !$connection->{finished};
    $connection = Foswiki::Contrib::PostgreContrib::getConnection('foswiki_users');
    $connection->{db};
}

1;

__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2008-2013 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
