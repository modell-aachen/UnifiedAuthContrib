#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
  if (-e './setlib.cfg') {
    unshift @INC, '.';
  } elsif (-e '../bin/setlib.cfg') {
    unshift @INC, '../bin';
  }

  require 'setlib.cfg';
}

use Foswiki;
use Foswiki::Func;
use Foswiki::Meta;

use Getopt::Long;

my %cfg = (
  list => 0,
  fix  => 0,
  host => '',
  form => 'UserForm',
  help => 0,
);

my %skip = (
  'AdminUser' => 1,
  'WikiGuest' => 1,
  'RegistrationAgent' => 1,
  'UnknownUser' => 1,
  'ProjectContributor' => 1,
);

Getopt::Long::GetOptions(
  'list|l'   => \$cfg{list},
  'fix|f'    => \$cfg{fix},
  'host=s'   => \$cfg{host},
  'form=s'   => \$cfg{form},
  'help|h'   => \$cfg{help},
);

sub _get {
  my @metas;
  my $it = Foswiki::Func::eachUser();
  while ($it->hasNext()) {
    my $user = $it->next();
    my $wikiname = Foswiki::Func::getWikiName($user);
    next if $skip{$wikiname};
    next unless Foswiki::Func::topicExists($Foswiki::cfg{UsersWebName}, $wikiname);
    my ($meta, $text) = Foswiki::Func::readTopic($Foswiki::cfg{UsersWebName}, $wikiname);
    my $form = $meta->getFormName() || '';
    next if $form eq $cfg{form};
    push @metas, $meta;
  }

  return \@metas;
}

sub _fix {
  my $metas = _get();
  foreach my $meta (@{$metas}) {
    print '   * Processing ' . $meta->topic() . '...';
    $meta->remove('FORM') if $meta->getFormName();
    $meta->put('FORM', {name => $cfg{form}});
    $meta->saveAs($meta->web(), $meta->topic(), (dontlog => 1, minor => 1, nohandlers => 1));
    $meta->finish();
    print " done\n";
  }
}

sub _list {
  my $metas = _get();
  foreach my $meta (@{$metas}) {
    print '   * ' . $meta->topic() . ', form: ' . ($meta->getFormName() || 'none') . "\n";
    $meta->finish();
  }
};

sub _process {
  new Foswiki('admin');
  _fix() if $cfg{fix};
  _list() if $cfg{list};
}

sub _help {
  my $help = <<HELP;

  -f    --fix             Attaches the specified form to each user topic.

        --form            The user form to list/attach.
                          Defaults to 'UserForm'.

  -l    --list            Lists all user topics which form name doesn't match the one supplied by parameter --form.

  -h    --help            Prints this help text.

        --host            VirtualHostingContrib only.
                          Either a virtual host name, e.g. 'foo.qwikinow.de', or 'all'.
                          If not supplied assume VirtualHostingContrib shall not be used.

HELP
  print $help;
}

sub _quit {
  my ($help, $exit) = @_;
  _help() if $help;
  exit $exit if defined $exit;
}

_quit(1, 0) if $cfg{help};
_quit(1, 1) unless $cfg{list} || $cfg{fix};
_quit(1, 1) unless $cfg{form};

$cfg{fix} = 0 if $cfg{list};
exit (_process() || 0) unless $cfg{host};

require Foswiki::Contrib::VirtualHostingContrib::VirtualHost;
if ($cfg{host} eq 'all') {
  Foswiki::Contrib::VirtualHostingContrib::VirtualHost->run_on_each(sub {
    my $host = $Foswiki::Contrib::VirtualHostingContrib::VirtualHost::CURRENT;
    print "Processing host $host\n";
    _process();
  });
} else {
  print "Processing host $cfg{host}\n";
  Foswiki::Contrib::VirtualHostingContrib::VirtualHost->run_on($cfg{host}, \&_process);
}

