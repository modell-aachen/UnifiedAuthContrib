#!/usr/bin/env perl
use strict;
use warnings;

do '../bin/setlib.cfg';
require Foswiki;
Foswiki->new('admin');

my $exclude = '';
my $logging = 0;
my $user = 'WikiGuest';
my @deny = ('DENYWEBVIEW','DENYWEBCHANGE','DENYWEBRENAME');
my $dry = 1;

unless(@ARGV){
  print "Automatically set/add users to ACL preferences\n";
  print "This tool does not do anything unless at least one of the following arguments is provided\n";
  print "\t- nodry={0|1} default 0, set to 1 if you want to save all changes, by default nothing is saved\n";
  print "\t- logging={0|1} default 0\n";
  print "\t- exclude={comma separated list of excluded webs}\n";
  print "\t- user={user or group to insert in DENYWEBVIEW}\n";
  print "\t- deny={comma separated list of DENYWEBVIEW,DENYWEBCHANGE,... default DENYWEBVIEW,DENYWEBCHANGE,DENYWEBRENAME}\n";
  exit;
}

foreach(@ARGV){
  my $ARG = $_;
  if($ARG =~ m/^exclude=(.*)/){
    $exclude = $1 if $1 ne '';
  }elsif($ARG =~ m/^logging=(.*)/){
    $logging = 1 if $1;
  }elsif($ARG =~ m/^user=(.*)/){
    $user = $1 if $1 ne '';
  }elsif($ARG =~ m/^deny=(.*)/){
    @deny = split(/,/,$1) if $1 ne'';
  }elsif($ARG =~ m/^nodry=(.*)/){
    $dry = 0 if $1;
  }
}

print "DRY: The PrefTopic will not be changed!\n" if $logging && $dry;

my $regex = "(";
my @excludeWebs = split(/,/,$exclude);
foreach (@excludeWebs) {
  $regex .= $_;
  if(\$_ != \$excludeWebs[-1]){
    $regex .= "|";
  }
}
$regex .= ")";

my @webs = Foswiki::Func::getListOfWebs();
foreach(@webs){
  my $web = $_;
  foreach(@deny){
    _setDENY($web,$_);
  }
}
1;

sub _setDENY{
  my $web = shift;
  my $denyvar = shift;

  $web =~ s/^\///;
  $web =~ s/\//./g;

  if($exclude ne '' && $web =~ m/^$regex$/){
    print "Exclude $web\r\n" if $logging;
    return;
  }
  my ($mainMeta, $mainText) = Foswiki::Func::readTopic($web, $Foswiki::cfg{WebPrefsTopicName});
  print "$web.$Foswiki::cfg{WebPrefsTopicName}: " if $logging;
  if(defined $mainText && $mainText ne ''){
      if ($mainText =~ m/Set $denyvar\s*=(.*)$/m) {
        my $deny = $1;
        if($deny =~ m/\b$user\b/){
          print "$user is allready in $denyvar\r\n" if $logging;
          return;
        }else{
          $deny =~ s/^\s+//;
          if($deny ne ''){
            $mainText =~ s/Set $denyvar\s*=\s*/Set $denyvar = $user,/g;
            print "Add User to $denyvar\r\n" if $logging;
          }else{
            $mainText =~ s/Set $denyvar\s*=\s*?\n/Set $denyvar = $user\n/g;
            print "Add User to $denyvar\r\n" if $logging;
          }
        }
    }else{
      print "Add $denyvar\r\n" if $logging;
      $mainText .= "\n   * Set $denyvar = $user\n";
    }
    #save modified WebPref
    unless($dry){
      Foswiki::Func::saveTopic($web, $Foswiki::cfg{WebPrefsTopicName}, $mainMeta, $mainText);
      print "Save Topic $web.$Foswiki::cfg{WebPrefsTopicName}\r\n" if $logging;
    }
  }
}

