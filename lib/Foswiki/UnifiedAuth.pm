package Foswiki::UnifiedAuth;

use strict;
use warnings;
use utf8;

use DBI;
use Encode;

use Foswiki::Contrib::PostgreContrib;
use Data::GUID;

my @schema_updates = (
    [
        "CREATE TABLE IF NOT EXISTS meta (type TEXT NOT NULL UNIQUE, version INT NOT NULL)",
        "INSERT INTO meta (type, version) VALUES('core', 0)",
        "CREATE TABLE IF NOT EXISTS providers (
            pid SERIAL,
            name TEXT NOT NULL
        )",
        "CREATE TABLE IF NOT EXISTS users (
            cuid UUID NOT NULL PRIMARY KEY,
            pid INTEGER NOT NULL,
            login_name TEXT NOT NULL,
            wiki_name TEXT NOT NULL,
            display_name TEXT NOT NULL,
            email TEXT NOT NULL,
            deactivated INTEGER DEFAULT 0
        )",
        "CREATE UNIQUE INDEX idx_wiki_name ON users (wiki_name)",
        "CREATE UNIQUE INDEX idx_cuid ON users (cuid)",
        "CREATE INDEX idx_login_name ON users (login_name)",
        "CREATE INDEX idx_email ON users (email)",
        "CREATE TABLE IF NOT EXISTS merged_users (
            primary_cuid UUID NOT NULL,
            mapped_cuid UUID NOT NULL,
            primary_provider INTEGER NOT NULL,
            mapped_provider INTEGER NOT NULL
        )",
        "CREATE UNIQUE INDEX idx_primary_cuid ON merged_users (primary_cuid)",
        "CREATE UNIQUE INDEX idx_mapped_cuid ON merged_users (mapped_cuid)",
        "CREATE TABLE IF NOT EXISTS groups (
            cuid UUID NOT NULL PRIMARY KEY,
            name TEXT NOT NULL,
            pid INTEGER NOT NULL
        )",
        "CREATE INDEX idx_groups ON groups (name)",
        "CREATE TABLE IF NOT EXISTS group_members (
            g_cuid UUID NOT NULL,
            u_cuid UUID NOT NULL,
            PRIMARY KEY (g_cuid, u_cuid)
        )",
        "CREATE INDEX idx_group_cuid ON group_members (g_cuid)",
        "CREATE INDEX idx_member_cuid ON group_members (u_cuid)",
        "CREATE TABLE IF NOT EXISTS nested_groups (
            parent UUID NOT NULL,
            child UUID NOT NULL,
            PRIMARY KEY (parent, child)
        )"
    ]
);

my $singleton;

sub new {
    my ($class) = @_;
    return $singleton if $singleton;
    my $this = bless {}, $class;

    $singleton = $this;
}

sub finish {
    $singleton->{connection}->finish if $singleton->{connection};
    undef $singleton->{db} if $singleton;
    undef $singleton;
}

sub db {
    my $this = shift;
    $this->connect unless defined $this->{db};
    $this->{db};
}

sub connect {
    my $this = shift;
    return $this->{db} if defined $this->{db};
    my $connection = Foswiki::Contrib::PostgreContrib::getConnection('foswiki_users');
    $this->{connection} = $connection;
    $this->{db} = $connection->{db};
    $this->{schema_versions} = {};
    eval {
        $this->{schema_versions} = $this->db->selectall_hashref("SELECT * FROM meta", 'type', {});
    };
    $this->apply_schema('core', @schema_updates);
}

sub apply_schema {
    my $this = shift;
    my $type = shift;
    my $db = $this->{db};

    if (!$this->{schema_versions}{$type}) {
        $this->{schema_versions}{$type} = { version => 0 };
    }

    my $v = $this->{schema_versions}{$type}{version};
    return if $v >= @_;
    for my $schema (@_[$v..$#_]) {
        $db->begin_work;
        for my $s (@$schema) {
            if (ref($s) eq 'CODE') {
                $s->($db);
            } else {
                $db->do($s);
            }
        }

        $db->do("UPDATE meta SET version=? WHERE type=?", {}, ++$v, $type);
        $db->commit;
    }
}

my %normalizers = (
    de => sub {
        my $wn = shift;
        $wn =~ s/Ä/Ae/g;
        $wn =~ s/Ö/Oe/g;
        $wn =~ s/Ü/Ue/g;
        $wn =~ s/ä/ae/g;
        $wn =~ s/ö/oe/g;
        $wn =~ s/ü/ue/g;
        $wn =~ s/ß/ss/g;
        $wn;
    }
);

sub guid {
    my $this = shift;
    Data::GUID->guid;
}

sub getCUID {
    my ($this, $user, $noUsers, $noGroups) = @_;

    my $db = $this->db;

    my $unescapedName = $user =~ s/_2d/-/gr;
    if(isCUID($unescapedName)) {
        unless ($noUsers) {
            my $fromDB = $db->selectrow_array('SELECT cuid FROM users WHERE cuid=?', {}, $unescapedName);
            return $fromDB if defined $fromDB;
        }

        unless ($noGroups) {
            my $fromDB = $db->selectrow_array('SELECT cuid FROM groups WHERE cuid=?', {}, $unescapedName);
            return $fromDB if defined $fromDB;
        }

        return undef; # not found
    }

    unless ($noUsers) {
        my $fromDB = $db->selectrow_array('SELECT cuid FROM users WHERE login_name=? OR wiki_name=?', {}, $user, $user);
        return $fromDB if defined $fromDB;
    }

    unless ($noGroups) {
        my $fromDB = $db->selectrow_array('SELECT cuid FROM groups WHERE name=?', {}, $user);

        return $fromDB if defined $fromDB;
    }

    return undef;
}

sub isCUID {
    my $login = shift;

    return $login =~ /^[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}$/;
}


sub add_user {
    my $this = shift;
    my ($charset, $authdomainid, $cuid, $email, $login_name, $wiki_name, $display_name, $deactivated) = @_;
    $deactivated = 0 unless defined $deactivated;

    _uni($charset, $cuid, $wiki_name, $display_name, $email);

    $cuid = $this->guid unless $cuid;

    my @normalizers = split(/\s*,\s*/, $Foswiki::cfg{UnifiedAuth}{WikiNameNormalizers} || '');
    foreach my $n (@normalizers) {
        next if $n =~ /^\s*$/;
        $wiki_name = $normalizers{$n}->($wiki_name);
    }
    eval {
        require Text::Unidecode;
        $wiki_name = Text::Unidecode::unidecode($wiki_name);
    };
    $wiki_name =~ s/([^a-z0-9])//gi;
    $wiki_name =~ s/^([a-z])/uc($1)/e;

    my $db = $this->db;
    my $has = sub {
        my $name = shift;
        return $db->selectrow_array("SELECT COUNT(wiki_name) FROM users WHERE wiki_name=?", {}, $name);
    };

    my $wn = $wiki_name;
    my $serial = 1;
    while ($has->($wn)) {
        $wn = $wiki_name . $serial++;
    }
    $wiki_name = $wn;

    $this->{db}->do("INSERT INTO users (cuid, pid, login_name, wiki_name, display_name, email, deactivated) VALUES(?,?,?,?,?,?,?)", {},
        $cuid, $authdomainid, $login_name, $wiki_name, $display_name, $email, $deactivated
    );
    return $cuid;
}

sub delete_user {
    my ($this, $cuid) = @_;

    $this->{db}->do("DELETE FROM users WHERE user_id=?", {}, $cuid);
}

sub _uni {
    my $charset = shift;
    for my $i (@_) {
        next if not defined $i || utf8::is_utf8($i);
        $i = decode($charset, $i);
    }
}

sub update_user {
    my ($this, $charset, $cuid, $email, $display_name, $deactivated) = @_;
    $deactivated = 0 unless defined $deactivated;
    _uni($charset, $cuid, $display_name, $email);
    return $this->db->do("UPDATE users SET display_name=?, email=?, deactivated=? WHERE cuid=?", {}, $display_name, $email, $deactivated, $cuid);
}

# Mockup for retrieval of users by search term.
# Does not yet support different fiels (login, email, ...).
sub queryUser {
    my ($this, $opts) = @_;
    my ($term, $maxrows, $page, $fields, $type, $basemapping) = (
        $opts->{term},
        $opts->{limit},
        $opts->{page},
        $opts->{searchable_fields},
        $opts->{type},
        $opts->{basemapping},
    );

    my $options = {Slice => {}};
    $maxrows = 10 unless defined $maxrows;
    $options->{MaxRows} = $maxrows if $maxrows;
    $page ||= 0;

    $term = '' unless defined $term;
    $term =~ s#^\s+##;
    $term =~ s#\s+$##;
    my @terms = split(/\s+/, $term);
    @terms = ('') unless @terms;
    @terms = map { "\%$_\%" } @terms;

    my $list;
    my $count;
    my $offset = $maxrows * $page;

    unless ($type eq 'groups') {
        my @params;
        @{$fields} = map {
            push @params, @terms;
            $_ =~ s/([A-Z])/'_'.lc($1)/ger =~ s/[^a-z_]//gr
        } @{$fields};

        my @parts;
        map {
            my $f = $_;
            push @parts, join(' AND ', map {"$f ILIKE ?"} @terms)
        } @$fields;

        my $u_condition = join(' OR ', @parts);
        if($basemapping eq 'skip') {
            my $session = $Foswiki::Plugins::SESSION;
            $u_condition = "($u_condition) AND pid!='" . $this->authProvider($session, '__baseuser')->getPid() . "'";
        } elsif ($basemapping eq 'adminonly') {
            my $session = $Foswiki::Plugins::SESSION;
            my $base = $this->authProvider($session, '__baseuser');
            my $admin = $base->getAdminCuid();
            my $pid = $base->getPid();
            $u_condition = "($u_condition) AND (pid !='$pid' OR cuid='$admin')";
        }

        my $g_condition = join(' AND ', map {
            push @params, @terms;
            "name ILIKE ?"
        } @terms) if $type eq 'any';

        my $statement;
        my $statement_count;
        if ($type eq 'any') {
            $statement = <<SQL;
SELECT
    'user' AS type,
    cuid AS cUID,
    login_name AS loginName,
    wiki_name as wikiName,
    display_name AS displayName,
    email
    FROM users
    WHERE deactivated=0 AND ($u_condition)
UNION
SELECT
    'group' AS type,
    cuid AS cUID,
    name AS wikiName,
    name AS displayName,
    '' AS loginName,
    '' AS email
    FROM groups
    WHERE ($g_condition)
ORDER BY displayName
OFFSET $offset
SQL
            $statement_count = <<SQL;
SELECT
    COUNT(*)
    FROM (
SELECT
    cuid
    FROM users
    WHERE deactivated=0 AND ($u_condition)
UNION
SELECT
    cuid
    FROM groups
    WHERE ($g_condition)
) AS gu
SQL
        } else {
            $statement = <<SQL;
SELECT
    'user' AS type,
    cuid AS cUID,
    login_name AS loginName,
    wiki_name as wikiName,
    display_name AS displayName
FROM users
WHERE deactivated=0 AND ($u_condition)
ORDER BY displayName
OFFSET $offset
SQL
            $statement_count = <<SQL;
SELECT
    count(*)
FROM users
WHERE deactivated=0 AND ($u_condition)
SQL
        }
        $list = $this->db->selectall_arrayref($statement, $options, @params);
        $count = $this->db->selectrow_array($statement_count, $options, @params);
    } else {
        my $condition = join(' AND ', map {"name ILIKE ?"} @terms);
            Foswiki::Func::writeWarning("condition: $condition");
        $list = $this->db->selectall_arrayref(<<SQL, $options, @terms);
SELECT
    'group' AS type,
    cuid AS cUID,
    name AS wikiName
FROM groups
WHERE ($condition)
ORDER BY wikiName
OFFSET $offset
SQL
        $count = $this->db->selectrow_array(<<SQL, $options, @terms);
SELECT
    COUNT(*)
FROM groups
WHERE ($condition)
SQL
    }

    return ($list, $count);
}

sub handleScript {
    my $session = shift;

    my $req = $session->{request};
    # TODO
}

sub authProvider {
    my ($this, $session, $id) = @_;

    return $this->{providers}->{$id} if $this->{providers}->{$id};

    my $cfg = $Foswiki::cfg{UnifiedAuth}{Providers}{$id};
    unless ($cfg) {
        if($id eq '__default') {
            $cfg = { config => {}, module => 'Default' };
        } elsif ($id eq '__baseuser') {
            $cfg = { config => {}, module => 'BaseUser' };
        } else {
            die "Provider not configured: $id";
        }
    }

    if ($cfg->{module} =~ /^Foswiki::Users::/) {
        die("Auth providers based on Foswiki password managers are not supported yet");
        #return Foswiki::UnifiedAuth::Providers::Passthrough->new($this->{session}, $id, $cfg);
    }

    my $package = "Foswiki::UnifiedAuth::Providers::$cfg->{module}";
    eval "require $package"; ## no critic (ProhibitStringyEval);
    if ($@ ne '') {
        use Carp qw(confess); confess("Failed loading auth: $id with $@");
        die "Failed loading auth provider: $@";
    }
    my $authProvider = $package->new($session, $id, $cfg->{config});

    $this->{providers}->{$id} = $authProvider;
    return $authProvider;
}

sub getPid {
    my ($this, $id) = @_;

    my $db = $this->db;
    my $pid = $db->selectrow_array("SELECT pid FROM providers WHERE name=?", {}, $id);

    return $pid if($pid);

    Foswiki::Func::writeWarning("Could not get pid of $id; creating a new one...");
    $db->do("INSERT INTO providers (name) VALUES(?)", {}, $id);
    return $this->getPid($id);
}

sub getOrCreateGroup {
    my ($this, $grpName, $pid) = @_;

    my $db = $this->{db};

    my $cuid = $db->selectrow_array(
        'SELECT cuid FROM groups WHERE name=? and pid=?', {}, $grpName, $pid);
    return $cuid if $cuid;

    $cuid = Data::GUID->guid;

    $db->begin_work;
    $db->do(
        'INSERT INTO groups (cuid, name, pid) VALUES(?, ?, ?)',
        {}, $cuid, $grpName, $pid);
    $db->commit;

    return $cuid;
}

sub removeGroup {
    my ($this, %group) = @_;

    # TODO: retain cuids and nestings in case the group re-appears (eg. malfunctioning ldap)

    my $db = $this->{db};

    my $cuid;
    if($group{cuid}) {
        $cuid = $group{cuid};
    } else {
        my $name = $group{name};
        my $pid = $group{pid};

        die unless $name && defined $pid; # XXX
        $cuid = $db->selectrow_array('SELECT cuid FROM groups WHERE name=? AND pid=?',
            {}, $name, $pid);
    }
    die unless $cuid; # XXX

    $db->begin_work;
    $db->do(
        'DELETE FROM groups WHERE cuid=?',
        {}, $cuid);
    $db->do(
        'DELETE FROM group_members WHERE g_cuid=?',
        {}, $cuid);
    $db->do(
        'DELETE FROM nested_groups WHERE parent=? OR child=?',
        {}, $cuid, $cuid);
    $db->commit;
}

sub updateGroup {
    my ($this, $pid, $group, $members, $nested) = @_;

    my $db = $this->{db};

    my $cuid = $this->getOrCreateGroup($group, $pid);

    my $currentMembers = {};
    my $currentGroups = {};

    # get current users
    { # scope
        my $fromDb = $db->selectcol_arrayref('SELECT u_cuid FROM group_members WHERE g_cuid=?', {}, $cuid);
        foreach my $item ( @$fromDb ) {
            $currentMembers->{$item} = 0;
        }
    }
    # get current nested groups
    { # scope
        my $fromDb = $db->selectcol_arrayref('SELECT child FROM nested_groups WHERE parent=?', {}, $cuid);
        foreach my $item ( @$fromDb ) {
            $currentGroups->{$item} = 0;
        }
    }

    $db->begin_work;
    # add users / groups
    foreach my $item ( @$members ) {
        unless(defined $currentMembers->{$item}) {
            $db->do('INSERT INTO group_members (g_cuid, u_cuid) VALUES(?,?)', {}, $cuid, $item);
        }
        $currentMembers->{$item} = 1;
    }
    foreach my $item ( @$nested ) {
        unless(defined $currentMembers->{$item}) {
            $db->do('INSERT INTO nested_groups (parent, child) VALUES(?,?)', {}, $cuid, $item);
        }
        $currentGroups->{$item} = 1;
    }

    # remove users/groups no longer present
    foreach my $item ( keys %$currentMembers ) {
        unless ($currentMembers->{$item}) {
            $db->do('DELETE FROM group_members WHERE g_cuid=? AND u_cuid=?', {}, $cuid, $item);
        }
    }
    foreach my $item ( keys %$currentGroups ) {
        unless ($currentGroups->{$item}) {
            $db->do('DELETE FROM nested_groups WHERE parent=? AND child=?', {}, $cuid, $item);
        }
    }
    $db->commit();
}


1;
