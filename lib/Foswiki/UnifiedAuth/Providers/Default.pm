package Foswiki::UnifiedAuth::Providers::Default;

use Error;

use strict;
use warnings;

our @ISA = qw(Foswiki::UnifiedAuth::Provider);

sub new {
    my ($class, $session, $id, $config) = @_;

    my $this = $class->SUPER::new($session, $id, $config);

    return $this;
}

sub useDefaultLogin {
    return 1;
}

sub initiateLogin {
    my ($this, $state, $force, $providers) = @_;

    my $session = $this->{session};
    my $query = $session->{request};
    my $context = Foswiki::Func::getContext();
    my $topic  = $session->{topicName};
    my $web    = $session->{webName};

    my $path_info = $query->path_info();
    if ( $path_info =~ m/['"]/g ) {
        $path_info = substr( $path_info, 0, ( ( pos $path_info ) - 1 ) );
    }

    $session->{prefs}->setSessionPreferences(
        FOSWIKI_ORIGIN => '',
        PATH_INFO => Foswiki::entityEncode($path_info),
        UAUTHSTATE => $state
    );

    my $tmpl = $session->templates->readTemplate('uauth');
    my $topicObject = Foswiki::Meta->new( $session, $web, $topic );
    $context->{uauth_login_default} = 1;

    my @forcables = ();
    foreach my $provider (@$providers) {
        my ($icon, $text) = $provider->forceButton();
        next unless $text;
        Foswiki::Func::setPreferencesValue('UAUTH_' . $provider->{id} . '_BUTTON_ICON', $icon);
        Foswiki::Func::setPreferencesValue('UAUTH_' . $provider->{id} . '_BUTTON_TEXT', $text);
        push @forcables, $provider->{id};
    }
    Foswiki::Func::setPreferencesValue('UAUTH_FORCIBLE_PROVIDERS', join(',', @forcables));

    $tmpl = $topicObject->expandMacros($tmpl); # TODO: hide user/password inputs when no provider supports it
    $tmpl = $topicObject->renderTML($tmpl);
    $tmpl =~ s/<nop>//g;
    $session->writeCompletePage($tmpl);

    return $state;
}

sub isMyLogin {
    my $this = shift;

    my $req = $this->{session}->{request};
    return 0 if $req->param('uauth_external');

    my $state = $req->param('state');
    return 0 unless $state;

    my $uauthlogin = $req->param('uauthlogin');
    return 1 if $uauthlogin && $uauthlogin eq 'default';

    return 0;
}

sub supportsRegistration {
    0;
}

sub processLogin {
    my ($this) = @_;

    my $session = $this->{session};
    my $req = $session->{request};
    my $cgis = $session->getCGISession();
    die with Error::Simple("Login requires a valid session; do you have cookies disabled?") if !$cgis;

    my $username = $req->param('username') || '';
    my $password = $req->param('password') || '';
    my $state = $req->param('state');
    $req->delete('username', 'password', 'state', 'uauthlogin', 'validation_key', 'uauth_external');

    my $uauth = Foswiki::UnifiedAuth->new();

    my @providers = sort keys %{$Foswiki::cfg{UnifiedAuth}{Providers}};
    push @providers, '__baseuser' unless grep(/^__baseuser$/, @providers);
    foreach my $name (@providers) {
        next if $name eq '__default';

        my $provider = $uauth->authProvider($session, $name);
        next unless $provider->enabled;
        next unless $provider->useDefaultLogin();

        my $result = $provider->processLoginData($username, $password);
        next unless $result;
        $result->{state} = $state;
        return $result;
    }
    my $error = $session->i18n->maketext("Wrong username or password");
    throw Error::Simple($error);
}

sub processUrl {
    my $this = shift;
    my $session = $this->{session};
    return $session->getScriptUrl(1, 'login');
}

1;
