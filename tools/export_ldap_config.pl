#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

do '../bin/setlib.cfg';
require Foswiki;
Foswiki->new('admin');

# Directly taken from the LdapContrib Config.spec
my $ldapContribDefaults = {
	'AllowChangePassword' => 0,
	'Base' => 'dc=my,dc=domain,dc=com',
	'BindDN' => '',
	'BindPassword' => 'secret',
	'CaseSensitiveLogin' => 0,
	'CharSet' => 'utf-8',
	'Debug' => 0,
	'DisplayAttributes' => 'displayName',
	'DisplayNameFormat' => '$cn',
	'Exclude' => 'WikiGuest, ProjectContributor, RegistrationAgent, AdminGroup, NobodyGroup',
	'GroupAttribute' => 'cn',
	'GroupBase' => ['ou=group,dc=my,dc=domain,dc=com'],
	'GroupFilter' => 'objectClass=group',
	'GroupScope' => 'sub',
	'Host' => 'ldap.my.domain.com',
	'IgnorePrivateGroups' => 1,
	'InnerGroupAttribute' => 'member',
	'IPv6' => 0,
	'KerberosKeyTab' => '/etc/krb5.keytab',
	'KnownReferralsOnly' => 0,
	'Krb5CredentialsCacheFile' => '',
	'LoginAttribute' => 'sAMAccountName',
	'LoginFilter' => 'objectClass=person',
	'MailAttribute' => 'mail',
	'MapGroups' => 1,
	'MaxCacheAge' => '',
	'MemberAttribute' => 'member',
	'MemberIndirection' => 1,
	'MergeGroups' => 0,
	'NormalizeGroupNames' => 0,
	'NormalizeLoginNames' => 0,
	'NormalizeWikiNames' => 1,
	'PageSize' => 200,
	'Port' => 389,
	'Precache' => 1,
	'PrimaryGroupAttribute' => 'gidNumber',
	'PrimaryGroupMapping' => {},
	'ReferralConfig' => {},
	'RewriteGroups' => {},
	'RewriteLoginNames' => [],
	'RewriteWikiNames' => { '^(.*)@.*$' => '$1' },
	'SASLMechanism' => 'PLAIN CRAM-MD5 EXTERNAL ANONYMOUS',
	'TLSCAFile' => '',
	'TLSCAPath' => '',
	'TLSClientCert' => '',
	'TLSClientKey' => '',
	'TLSSSLVersion' => 'tlsv1',
	'TLSVerify' => 'require',
	'UserBase' => ['ou=people,dc=my,dc=domain,dc=com'],
	'UserMappingTopic' => '',
	'UserScope' => 'sub',
	'UseSASL' => 0,
	'UseTLS' => 0,
	'Version' => 3,
	'WikiGroupsBackoff' => 1,
	'WikiNameAliases' => '',
	'WikiNameAttributes' => 'givenName,sn',
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
$Data::Dumper::Sortkeys = 1;
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
#Set MapGroups parameter per default to 1, to ensure groups get imported
$oldConfig->{MapGroups} = 1;
my $result = Dumper($oldConfig);
print $result;
