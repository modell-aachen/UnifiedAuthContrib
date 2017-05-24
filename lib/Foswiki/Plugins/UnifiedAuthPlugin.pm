# See bottom of file for license and copyright information

package Foswiki::Plugins::UnifiedAuthPlugin;

use strict;
use warnings;

use Foswiki::Func;
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

    Foswiki::Func::registerRESTHandler( 'registerUser',
                                        \&_registerUser,
                                        authenticate => 0,
                                        validate => 0,
                                        http_allow => 'POST',
                                      );

    Foswiki::Func::registerRESTHandler( 'users',
                                        \&_RESTusers,
                                        authenticate => 0,
                                        validate => 0,
                                        http_allow => 'POST',
                                      );

    Foswiki::Func::registerRESTHandler( 'groups',
                                        \&_RESTgroups,
                                        authenticate => 0,
                                        validate => 0,
                                        http_allow => 'GET',
                                      );
    Foswiki::Func::registerRESTHandler( 'addUsersToGroup',
                                        \&_addUsersToGroup,
                                        authenticate => 0,
                                        validate => 0,
                                        http_allow => 'POST',
                                      );
    Foswiki::Func::registerRESTHandler( 'removeUserFromGroup',
                                        \&_removeUserFromGroup,
                                        authenticate => 0,
                                        validate => 0,
                                        http_allow => 'POST',
                                      );
    Foswiki::Func::registerRESTHandler( 'resetPassword',
                                        \&_resetPassword,
                                        authenticate => 0,
                                        validate => 0,
                                        http_allow => 'POST',
                                      );
    return 1;
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
  my $auth = Foswiki::UnifiedAuth->new();

  $q->{path_info} =~ /$subject\/$verb\/?(.*?)\/?$/;
  my $entity = $1;
  if($entity){
    #TODO: Get/modify user entity
  }
  else{
    # TODO: Create user/get users
  }


  my $id = $q->param("id");
}

sub _RESTgroups {
  my ($session, $subject, $verb, $response) = @_;
  my $q = $session->{request};
  my $auth = Foswiki::UnifiedAuth->new();

  $q->{path_info} =~ /$subject\/$verb\/?(.*?)\/?$/;
  my $entity = $1;
  if($entity){
    #TODO: Get/modifiy group entity
  }
  else{
    my $db = _getConnection();
    my $baseQuery = "select groups.name as name,groups.cuid as id from groups inner join providers on (groups.pid=providers.pid) where providers.name='__uauth'";
    my $groups =  $db->selectall_arrayref($baseQuery, {Slice => {}});
    return to_json($groups);
  }


  my $id = $q->param("id");
}

sub _addUsersToGroup {
  my ($session, $subject, $verb, $response) = @_;
  my $q = $session->{request};
  my $auth = Foswiki::UnifiedAuth->new();

  my $group = $q->param("group[name]");
  #TODO: use more then one cuid
  my $cuids = $q->param("cuids");
  #TODO: also need more then one wikiName
  my $wikiName = $q->param("wikiName");

  unless ($group and $cuids){
    $response->header(-status => 400);
    return to_json({status=> 'error', msg => "Missing params"});
  }

  eval {
      my $userMapping = Foswiki::Users::UnifiedUserMapping->new($session);
      $userMapping->addUserToGroup($cuids, $group);
      my $indexProvider = $auth->authProvider($session, $auth->getProviderForUser($wikiName));
      $indexProvider->indexUser($cuids);
  };
  if($@){
    $response->header(-status => 404);
    Foswiki::Func::writeWarning($@);
    return to_json({status => 'error', msg => "User could not be added to group."});
  }

  return to_json({status => "ok"});
}

sub _removeUserFromGroup {
  my ($session, $subject, $verb, $response) = @_;
  my $q = $session->{request};
  my $auth = Foswiki::UnifiedAuth->new();

  my $group = $q->param("group");
  #TODO: use more then one cuid
  my $cuids = $q->param("cuids");
  #TODO: also need more then one wikiName
  my $wikiName = $q->param("wikiName");

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
    $response->header(-status => 404);
    Foswiki::Func::writeWarning($@);
    return to_json({status => 'error', msg => "User could not be removed from group."});
  }

  return to_json({status => "ok"});
}

sub _resetPassword {
  my ($session, $subject, $verb, $response) = @_;
  my $q = $session->{request};
  my $auth = Foswiki::UnifiedAuth->new();

  my $cuid = $q->param("cuid");
  my $wikiName = $q->param("wikiName");

  #TODO: Check if topic user
  unless ($wikiName and $cuids){
    $response->header(-status => 400);
    return to_json({status=> 'error', msg => "Missing params"});
  }
  #TODO: Send Mail with reset link.

  return to_json({status => "ok"});
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
