#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

do '../bin/setlib.cfg';
require Foswiki;
Foswiki->new('admin');

# Directly taken from the LdapContrib Config.spec
my $ldapContribDefaults = {
	'Host' => 'ldap.my.domain.com',
	'Port' => 389,
	'IPv6' => 0,
	'Version' => 3,
	'Base' => 'dc=my,dc=domain,dc=com',
	'BindDN' => '',
	'BindPassword' => 'secret',
	'KerberosKeyTab' => '/etc/krb5.keytab',
	'CharSet' => 'utf-8',
	'UseSASL' => 0,
	'SASLMechanism' => 'PLAIN CRAM-MD5 EXTERNAL ANONYMOUS',
	'Krb5CredentialsCacheFile' => '',
	'ReferralConfig' => {},
	'KnownReferralsOnly' => 0,
	'UseTLS' => 0,
	'TLSSSLVersion' => 'tlsv1',
	'TLSVerify' => 'require',
	'TLSCAPath' => '',
	'TLSCAFile' => '',
	'TLSClientCert' => '',
	'TLSClientKey' => '',
	'Debug' => 0,
	'UserBase' => ['ou=people,dc=my,dc=domain,dc=com'],
	'LoginFilter' => 'objectClass=person',
	'UserScope' => 'sub',
	'LoginAttribute' => 'sAMAccountName',
	'MailAttribute' => 'mail',
	'DisplayAttributes' => 'displayName',
	'DisplayNameFormat' => '$displayName',
	'WikiNameAttributes' => 'givenName,sn',
	'NormalizeWikiNames' => 1,
	'NormalizeLoginNames' => 0,
	'CaseSensitiveLogin' => 0,
	'WikiNameAliases' => '',
	'RewriteWikiNames' => { '^(.*)@.*$' => '$1' },
	'RewriteLoginNames' => [],
	'AllowChangePassword' => 0,
	'UserMappingTopic' => '',
	'GroupBase' => ['ou=group,dc=my,dc=domain,dc=com'],
	'GroupFilter' => 'objectClass=group',
	'GroupScope' => 'sub',
	'GroupAttribute' => 'cn',
	'PrimaryGroupAttribute' => 'gidNumber',
	'MemberAttribute' => 'member',
	'InnerGroupAttribute' => 'member',
	'MemberIndirection' => 1,
	'WikiGroupsBackoff' => 1,
	'NormalizeGroupNames' => 0,
	'IgnorePrivateGroups' => 1,
	'MapGroups' => 1,
	'RewriteGroups' => {},
	'PrimaryGroupMapping' => {},
	'MergeGroups' => 0,
	'MaxCacheAge' => 86400,
	'Precache' => 1,
	'PageSize' => 500,
	'Exclude' => 'WikiGuest, ProjectContributor, RegistrationAgent, UnknownUser, AdminGroup, NobodyGroup, AdminUser, admin, guest'
};

# All the settings defined in the LdapNgPlugin can be excluded
my $ldapContribRemove = {
	'DefaultAutocompleteFields' => 1,
	'PersonDataForm' => 1,
	'PersonAttribures' => 1,
	'IndexEmails' => 1,
	'PreferLocalSettings' => 1,
	'DefaultCacheExpire' => 1,
	'IgnoreViewRightsInSearch' => 1
};

$Data::Dumper::Terse = 1;
no warnings 'once';
my $oldConfig = $Foswiki::cfg{Ldap};
foreach my $key (keys(%$oldConfig)){
	if($ldapContribRemove->{$key}){
		delete $oldConfig->{$key};
	}
	if(Dumper($oldConfig->{$key}) eq Dumper($ldapContribDefaults->{$key})){
		delete $oldConfig->{$key};
	}
}
my $result = Dumper($oldConfig);
print $result;