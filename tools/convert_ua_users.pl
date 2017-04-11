#! /usr/bin/env perl
# Converter that rewrites user info to GUID based cUIDs:
# - Form fields
# - Workflow info (LASTPROCESSOR, LEAVING, WRKFLWCONTRIBUTORS)
# - ACLs
# - MetaCommentPlugin
#
# For form fields, only type 'user'/'user+multi' is processed, so you have to
# update the forms before running this.
#
# Only PlainFileStore is supported. Please convert before you do this.
#
# No arguments required - unless you want virtualhosting, then either pass
# --host=all or --host=my.host.name
# or set a host environment variable.
#
# No backups are made; that's your job.

# Copyright 2016 Modell Aachen GmbH
# License: GPLv2+

use strict;
use warnings;

# Set library paths in @INC, at compile time
BEGIN {
  if (-e './setlib.cfg') {
    unshift @INC, '.';
  } elsif (-e '../bin/setlib.cfg') {
    unshift @INC, '../bin';
  }
  require 'setlib.cfg';
}

my %formcache;
my $session;
my %users;
my $usercount;

my $hostname = $ENV{host};
unless ($hostname) {
    foreach my $arg (@ARGV) {
        if($arg =~ m#(?:--)?host=(\S+)#) {
            $hostname = $1;
        }
    }
}

use Data::GUID;
use Foswiki ();

if ($hostname) {
    require Foswiki::Contrib::VirtualHostingContrib;
    require Foswiki::Contrib::VirtualHostingContrib::VirtualHost;
}

sub convert {
    $session = Foswiki->new('admin');

    %users = ();
    $usercount = 0;

    my $uit = Foswiki::Func::eachUser();
    while ($uit->hasNext) {
        my $u = $uit->next;
        my $cuid = Foswiki::Func::getCanonicalUserID($u);
        my $login = Foswiki::Func::wikiToUserName($u);

        next if $cuid =~ /^BaseUserMapping/;
        print STDERR "Skipping wikiname $u: No available login information!\n" unless $login;
        next unless $login;

        eval {
            Data::GUID->from_string($cuid);
        };
        if ($@) {
            print STDERR "Skipping wikiname $u: No valid cUID available. Got $cuid!\n";
            next;
        }

        $users{$login} = $cuid;
        $users{$login =~ s/([^a-zA-Z0-9])/'_'.sprintf('%02x', ord($1))/ger} = $cuid;
        $usercount++;
    }
    print STDERR "Loaded information about $usercount users.\n";

    my $keepmsg = 1;
    for my $web (Foswiki::Func::getListOfWebs("user")) {
        TOPIC: for my $topic (Foswiki::Func::getTopicList($web)) {
            my $topicfile = "$Foswiki::cfg{DataDir}/$web/$topic.txt";
            my $pfvdir = "$Foswiki::cfg{DataDir}/$web/$topic,pfv";

            my $haspfv = -d $pfvdir;
            opendir(my $pfvh, $pfvdir) or warn("Can't read revisions dir $pfvdir: $!") if $haspfv;

            if (!$keepmsg) {
                print STDERR "\033[F\033[K";
            }
            $keepmsg = 0;
            print STDERR "$web.$topic: (current)";

            my $res = treatFile($web, $topicfile);
            $keepmsg = 1 if !$res || $res == 2;
            next unless $res;
            my $f;
            while ($haspfv and $f = readdir($pfvh)) {
                if($f =~ m/^\d+\.m$/) {
                    treatMetaFile($web, "$pfvdir/$f");
                }
                next unless $f =~ /^\d+$/;
                print STDERR "($f)";
                $res = treatFile($web, "$pfvdir/$f");
                $keepmsg = 1 if !$res || $res == 2;
                next TOPIC unless $res;
            }
            print STDERR ".\n";
        }
    }
    if (!$keepmsg) {
        print STDERR "\033[F\033[K";
    }
}

# Rewrite history meta file (.m)
sub treatMetaFile {
    my ($web, $filename) = @_;

    open(my $tfh, '<:utf8', $filename) or warn("Can't open $filename: $!") && return;
    local $/;

    my $l = <$tfh>;
    close($tfh);
    my $origL = $l;

    $l =~ s/^(\S+)/_mapUser($1)/e;
    return 1 if $l eq $origL;
    open($tfh, '>:utf8', $filename) or warn("Can't open $filename for writing: $!") && return;
    print $tfh $l;
    close($tfh);
    print STDERR "*";
    2;
}

# Rewrite a file (.txt or PFS version file)
sub treatFile {
    my ($web, $filename) = @_;

    open(my $tfh, '<:utf8', $filename) or warn("Can't open $filename: $!") && return;
    local $/;
    my $l = <$tfh>;

    my ($formraw) = $l =~ /^%META:FORM\{name="(.*?)"\}%$/m;
    my $fields = [];
    if ($formraw) {
        my ($fweb, $ftopic) = Foswiki::Func::normalizeWebTopicName($web, $formraw);
        $formraw = "$fweb.$ftopic";
        $fields = $formcache{$formraw};
        if (!$fields) {
            $fields = [];
            my $form;
            eval {
                $form = Foswiki::Form->new($session, $fweb, $ftopic);
            };
            unless ($@) {
                for my $f (@{$form->getFields}) {
                    next unless $f->isa('Foswiki::Form::User');
                    push @$fields, $f;
                }
            } else {
                print STDERR "Error loading form: `$formraw'";
            }
            $formcache{$formraw} = $fields;
        }
    }

    my $haswf = ($l =~ /^%META:WORKFLOW\{/m);

    my $origL = $l;
    close($tfh);
    for my $f (@$fields) {
        $l =~ s/^(%META:FIELD\{name="$f->{name}".*?value=")(.*)(".*\}%)$/$1. _mapUsersField($f, $2) .$3/em;
    }
    if ($haswf) {
        $l =~ s/^(%META:WORKFLOW\{)(.*)(\}%)$/$1. _mapTag($2, '^(?:LASTPROCESSOR_|LEAVING_)' => 0) .$3/em;
        $l =~ s/^(%META:WRKFLWCONTRIBUTORS\{)(.*)(\}%)$/$1. _mapTag($2, '^value$' => 1) .$3/em;
    }

    # Comments
    $l =~ s/^(%META:COMMENT\{)(.*)(\}%)$/$1. _mapTag($2, '^(?:read|notified)$' => 1, '^author$' => 0) .$3/egm;

    # Preferences
    $l =~ s/^(%META:PREFERENCE\{)(.*)(\}%)$/$1. _mapTag($2, '^(?:ALLOW|DENY)TOPIC' => 1) .$3/egm;
    $l =~ s/^((?:   )+\*\s+Set\s+(\w+)\s+=\s+)([^\015\012]*)$/$1. _mapPref($2, $3)/egm;

    # Task changesets
    $l =~ s/^(%META:TASKCHANGESET\{)(.*)(\}%)$/$1. _mapTag($2, '^actor$' => 0) .$3/egm;

    return 1 if $l eq $origL;
    open($tfh, '>:utf8', $filename) or warn("Can't open $filename for writing: $!") && return;
    print $tfh $l;
    close($tfh);
    print STDERR "*";
    2;
}

# Map a single name to its cUID (unless it's unknown or already mapped).
sub _mapUser {
    my ($v) = @_;
    $v =~ s/^\s+|\s+$//g;
    my $shortV = $v =~ s/^(?:Main|%USERSWEB%)\.//r;
    return $users{$shortV} ? $users{$shortV} : $v;
}

# Map a comma-separated list of names to their cUIDs. Skip unknown/already mapped entries.
sub _mapUserMulti {
    my @v = map { _mapUser($_) } split(/\s*,\s*/, $_[0]);
    return join(', ', @v);
}

# Map a form field, automatically detecting multi-valuedness.
sub _mapUsersField {
    my ($f, $v) = @_;
    return _mapUserMulti($v) if $f->isMultiValued;
    return _mapUser($v);
}

# Rewrite the params list of a META tag or macro.
# This gets passed a regex->flag hash.
# If a regex matches, the multi-user mapping is applied if the flag is true; otherwise the single-user mapping is used.
sub _mapTag {
    my ($attrString, %map) = @_;
    my $attr = Foswiki::Attrs->new($attrString);
    while (my ($k, $v) = each(%$attr)) {
        my $last = 0; # XXX workaround for 'last' command skipping next iteration
        while (my ($mk, $mv) = each(%map)) {
            next unless $k =~ /$mk/;
            $attr->{$k} = $mv ? _mapUserMulti($v) : _mapUser($v) unless $last;
            $last = 1; # last;
        }
    }
    $attr->stringify;
}

# Helper for mapping preferences in topic text
sub _mapPref {
    my ($pref, $v) = @_;

    return $v unless $pref =~ /^(?:ALLOW|DENY)(?:TOPIC|WEB|ROOT)/;
    _mapUserMulti($v);
}

if ($hostname) {
    if($hostname eq 'all') {
        Foswiki::Contrib::VirtualHostingContrib::VirtualHost->run_on_each(\&convert);
    } else {
        Foswiki::Contrib::VirtualHostingContrib::VirtualHost->run_on($hostname, \&convert);
    }
} else {
    convert();
}

print STDERR "\nDone.\n";
