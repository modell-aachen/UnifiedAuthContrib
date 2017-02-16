#!/usr/bin/env perl
use strict;
use warnings;

# Set/Add user in DENYWEBVIEW
# Parameter:
#   - logging={0|1}
#   - exclude={comma separated list of excluded webs}
#   - user={user or group to insert in DENYWEBVIEW}
#

do '../bin/setlib.cfg';
require Foswiki;
Foswiki->new('admin');

my $dataDir = '../data';

my $exclude = '';
my $logging = 0;
my $user = 'WikiGuest';

foreach(@ARGV){
  my $ARG = $_;
  if($ARG =~ m/^exclude=(.*)/){
    $exclude = $1 if $1 ne '';
  }elsif($ARG =~ m/^logging=(.*)/){
    $logging = 1 if $1;
  }elsif($ARG =~ m/^user=(.*)/){
    $user = $1 if $1 ne '';
  }
}

my $regex = "(";
my @excludeWebs = split(/,/,$exclude);
foreach (@excludeWebs) {
  $regex .= $_;
  if(\$_ != \$excludeWebs[-1]){
    $regex .= "|";
  }
}
$regex .= ")";

_searchDirs($dataDir);

1;


#set wikiguest to DENYWEBVIEW
sub _setDENYWEBVIEW{
  my $dir = shift;
  #get WebPref
  $dir =~ s/$dataDir//;
  $dir =~ s/^\///;

  if($exclude ne '' && $dir =~ m/^$regex/){
    print "Exclude $dir\r\n" if $logging;
    return;
  }
  my ($mainMeta, $mainText) = Foswiki::Func::readTopic($dir, "WebPreferences");
  print $dir.".WebPreferences: " if $logging;
  if(defined $mainText && $mainText ne ''){
      if ($mainText =~ m/Set DENYWEBVIEW = (.*)\n/) {
        my $deny = $1;
        if($deny =~ m/$user/){
          print "$user is allready in\r\n" if $logging;
          return;
        }else{
          $deny =~ s/^\s+//;
          if($deny ne ''){
            $mainText =~ s/Set DENYWEBVIEW = /Set DENYWEBVIEW = $user,/g;
            print "Add User to DENYWEBVIEW\r\n" if $logging;
          }else{
            $mainText =~ s/Set DENYWEBVIEW = /Set DENYWEBVIEW = $user/g;
            print "Add User to DENYWEBVIEW\r\n" if $logging;
          }
        }
    }else{
      print "Add DENYWEBVIEW\r\n" if $logging;
      $mainText .= "\n   * Set DENYWEBVIEW = $user\n";
    }
    #save modified WebPref
    Foswiki::Func::saveTopic($dir, "WebPreferences", $mainMeta, $mainText);
  }
}

#search recursiv webs
sub _searchDirs {
  my $dir = shift;

  my $file;
  opendir(DIR, $dir) || die "Unable to open $dir: $!";
  my(@files) = grep {!/^\.\.?$/ } readdir(DIR);
  closedir(DIR);
  foreach (@files) {
    if ( -d ($file = "$dir/$_") && $file !~ m/,pfv/)  {
      _setDENYWEBVIEW($file);
      _searchDirs($file);
    }
  }
}
