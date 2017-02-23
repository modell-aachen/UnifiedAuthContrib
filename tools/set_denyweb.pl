#!/usr/bin/env perl
use strict;
use warnings;

# Set/Add user in DENYWEBVIEW
# Parameter:
#   - logging={0|1} default 0
#   - exclude={comma separated list of excluded webs}
#   - user={user or group to insert in DENYWEBVIEW}
#   - deny={comma separated list of DENYWEBVIEW,DENYWEBCHANGE,... default DENYWEBVIEW,DENYWEBCHANGE}
#   - dry={0|1} default 0, set if you do not want to change just to see what will be changed
#

do '../bin/setlib.cfg';
require Foswiki;
Foswiki->new('admin');

my $exclude = '';
my $logging = 0;
my $user = 'WikiGuest';
my @deny = ('DENYWEBVIEW','DENYWEBCHANGE');
my $dry = 0;

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
  }elsif($ARG =~ m/^dry=(.*)/){
    $dry = 1 if $1;
  }
}

print "DRY: The PrefTopic will not be changed!" if $logging && $dry;

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


#set wikiguest to DENYWEBVIEW
sub _setDENY{
  my $dir = shift;
  my $denyvar = shift;
  #get WebPref
#  $dir =~ s/$dataDir//;
  $dir =~ s/^\///;
  $dir =~ s/\//./g;

  if($exclude ne '' && $dir =~ m/^$regex/){
    print "Exclude $dir\r\n" if $logging;
    return;
  }
  my ($mainMeta, $mainText) = Foswiki::Func::readTopic($dir, $Foswiki::cfg{WebPrefsTopicName});
  print "$dir.$Foswiki::cfg{WebPrefsTopicName}: " if $logging;
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
      Foswiki::Func::saveTopic($dir, $Foswiki::cfg{WebPrefsTopicName}, $mainMeta, $mainText);
      print "Save Topic $dir.$Foswiki::cfg{WebPrefsTopicName}\r\n" if $logging;
    }
  }
}

