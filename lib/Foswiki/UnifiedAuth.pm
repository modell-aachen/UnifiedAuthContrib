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
        "CREATE TABLE meta (type TEXT NOT NULL UNIQUE, version INT NOT NULL)",
        "INSERT INTO meta (type, version) VALUES('core', 0)",
        "CREATE TABLE providers (
            pid SERIAL,
            name TEXT NOT NULL
        )",
        "CREATE TABLE users (
            cuid UUID NOT NULL PRIMARY KEY,
            pid INTEGER NOT NULL,
            login_name TEXT NOT NULL,
            wiki_name TEXT NOT NULL,
            display_name TEXT NOT NULL,
            email TEXT NOT NULL
        )",
        "CREATE UNIQUE INDEX idx_wiki_name ON users (wiki_name)",
        "CREATE UNIQUE INDEX idx_cuid ON users (cuid)",
        "CREATE INDEX idx_login_name ON users (login_name)",
        "CREATE INDEX idx_email ON users (email)",
        "CREATE TABLE merged_users (
            primary_cuid UUID NOT NULL,
            mapped_cuid UUID NOT NULL,
            primary_provider INTEGER NOT NULL,
            mapped_provider INTEGER NOT NULL
        )",
        "CREATE UNIQUE INDEX idx_primary_cuid ON merged_users (primary_cuid)",
        "CREATE UNIQUE INDEX idx_mapped_cuid ON merged_users (mapped_cuid)",
        "CREATE TABLE groups (
            cuid UUID NOT NULL PRIMARY KEY,
            name TEXT NOT NULL
        )",
        "CREATE INDEX idx_groups ON groups (name)",
        "CREATE TABLE group_members (
            g_cuid UUID NOT NULL,
            u_cuid UUID NOT NULL,
            PRIMARY KEY (g_cuid, u_cuid)
        )",
        "CREATE INDEX idx_group_cuid ON group_members (g_cuid)",
        "CREATE INDEX idx_member_cuid ON group_members (u_cuid)",
        "CREATE TABLE nested_groups (
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

sub add_user {
    my $this = shift;
    my ($charset, $authdomainid, $cuid, $email, $login_name, $wiki_name, $display_name) = @_;

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

    $this->{db}->do("INSERT INTO users (cuid, pid, login_name, wiki_name, display_name, email) VALUES(?,?,?,?,?,?)", {},
        $cuid, $authdomainid, $login_name, $wiki_name, $display_name, $email
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
    my ($this, $charset, $cuid, $email, $display_name) = @_;
    _uni($charset, $cuid, $display_name, $email);
    return $this->db->do("UPDATE users SET display_name=?, email=? WHERE cuid=?", {}, $display_name, $email, $cuid);
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
        if($id eq 'default') {
            $cfg = { config => {}, module => 'Default' };
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


1;
