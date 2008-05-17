# XXX CARGO CULTED FROM SVK::Util;
package Prophet::Replica::SVN::Util;
use Moose;
use MooseX::ClassAttribute;

use SVN::Client;

my $pool = SVN::Pool->new;

=head1 NAME

Prophet::Replica::SVN

=head1 DESCRIPTION

A library of utility functions for Subversion repository authentication. Ripped from SVK

=cut

class_has svnconfig => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        my $self = shift;
        return undef if $ENV{PROPHET_NO_SVN_CONFIG};

        SVN::Core::config_ensure(undef);
        return $self->_svnconfig( SVN::Core::config_get_config( undef, $pool ) );
    },
);

# XXX: this is 1.3 api. use SVN::Auth::* for 1.4 and we don't have to load ::Client anymore
# (well, fix svn perl bindings to wrap the prompt functions correctly first.

class_has auth_providers => (
    is      => 'rw',
    lazy    => 1,
    default => sub { sub {
        my $keychain = SVN::_Core->can('svn_auth_get_keychain_simple_provider');
        my $win32    = SVN::_Core->can('svn_auth_get_windows_simple_provider');
        [   $keychain ? $keychain : (),
            $win32    ? $win32    : (),
            SVN::Client::get_simple_provider(),
            SVN::Client::get_ssl_server_trust_file_provider(),
            SVN::Client::get_username_provider(),
            SVN::Client::get_simple_prompt_provider( \&_simple_prompt, 2 ),
            SVN::Client::get_ssl_server_trust_prompt_provider( \&_ssl_server_trust_prompt ),
            SVN::Client::get_ssl_client_cert_prompt_provider( \&_ssl_client_cert_prompt, 2 ),
            SVN::Client::get_ssl_client_cert_pw_prompt_provider( \&_ssl_client_cert_pw_prompt, 2 ),
            SVN::Client::get_username_prompt_provider( \&_username_prompt, 2 ),
        ];
    }},
);


=head2 svnconfig

Returns a handle to the user's Subversion configuration.

=cut

=head2 get_auth_providers

Returns an array of Subversion authentication providers

# Note: Use a proper default pool when calling get_auth_providers

=cut

sub get_auth_providers {
    my $class = shift;
    return $class->auth_providers->();
}

use constant OK => $SVN::_Core::SVN_NO_ERROR;

# Implement auth callbacks
sub _simple_prompt {
    my ( $cred, $realm, $default_username, $may_save, $pool ) = @_;

    if ( defined $default_username and length $default_username ) {
        print "Authentication realm: $realm\n" if defined $realm and length $realm;
        $cred->username($default_username);
    } else {
        _username_prompt( $cred, $realm, $may_save, $pool );
    }

    $cred->password( _read_password( "Password for '" . $cred->username . "': " ) );
    $cred->may_save($may_save);

    return OK;
}

sub _ssl_server_trust_prompt {
    my ( $cred, $realm, $failures, $cert_info, $may_save, $pool ) = @_;

    print "Error validating server certificate for '$realm':\n";

    print " - The certificate is not issued by a trusted authority. Use the\n",
        "   fingerprint to validate the certificate manually!\n"
        if ( $failures & $SVN::Auth::SSL::UNKNOWNCA );

    print " - The certificate hostname does not match.\n"
        if ( $failures & $SVN::Auth::SSL::CNMISMATCH );

    print " - The certificate is not yet valid.\n"
        if ( $failures & $SVN::Auth::SSL::NOTYETVALID );

    print " - The certificate has expired.\n"
        if ( $failures & $SVN::Auth::SSL::EXPIRED );

    print " - The certificate has an unknown error.\n"
        if ( $failures & $SVN::Auth::SSL::OTHER );

    printf(
        "Certificate information:\n"
            . " - Hostname: %s\n"
            . " - Valid: from %s until %s\n"
            . " - Issuer: %s\n"
            . " - Fingerprint: %s\n",
        map $cert_info->$_,
        qw(hostname valid_from valid_until issuer_dname fingerprint)
    );

    print( $may_save
        ? "(R)eject, accept (t)emporarily or accept (p)ermanently? "
        : "(R)eject or accept (t)emporarily? "
    );

    my $choice = lc( substr( <STDIN> || 'R', 0, 1 ) );

    if ( $choice eq 't' ) {
        $cred->may_save(0);
        $cred->accepted_failures($failures);
    } elsif ( $may_save and $choice eq 'p' ) {
        $cred->may_save(1);
        $cred->accepted_failures($failures);
    }

    return OK;
}

sub _ssl_client_cert_prompt {
    my ( $cred, $realm, $may_save, $pool ) = @_;

    print "Client certificate filename: ";
    chomp( my $filename = <STDIN> );
    $cred->cert_file($filename);

    return OK;
}

sub _ssl_client_cert_pw_prompt {
    my ( $cred, $realm, $may_save, $pool ) = @_;

    $cred->password( _read_password("Passphrase for '%s': ") );

    return OK;
}

sub _username_prompt {
    my ( $cred, $realm, $may_save, $pool ) = @_;

    print "Authentication realm: $realm\n" if defined $realm and length $realm;
    print "Username: ";
    chomp( my $username = <STDIN> );
    $username = '' unless defined $username;

    $cred->username($username);

    return OK;
}

sub _read_password {
    my ($prompt) = @_;

    print $prompt;

    require Term::ReadKey;
    Term::ReadKey::ReadMode('noecho');

    my $password = '';
    while ( defined( my $key = Term::ReadKey::ReadKey(0) ) ) {
        last if $key =~ /[\012\015]/;
        $password .= $key;
    }

    Term::ReadKey::ReadMode('restore');
    print "\n";

    return $password;
}

1;
