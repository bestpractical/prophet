use warnings;
use strict;

use Prophet::Test tests => 5;
use File::Temp qw(tempdir);

$ENV{'PROPHET_REPO'} = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG}  ) . '/repo-' . $$;

# try to make prophet clone explode by feeding it bogus URLs

(undef, my $error) = run_command( 'clone', '--from', 'malformed-url' );
is( $error, <<EOM
I don't know how to handle the replica URL you provided - 'malformed-url'.
Is your syntax correct?
EOM
, 'malformed url errors out' );

$ENV{'PROPHET_REPO'} = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG}  ) . '/repo-' . $$;
(undef, $error) = run_command( 'clone', '--from', 'sqlite:foo' );
is( $error, <<EOM
I couldn't determine a filesystem root from the given URL.
Correct syntax is (sqlite:)file:///replica/root .
EOM
, 'sqlite:foo errors out' );

$ENV{'PROPHET_REPO'} = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG}  ) . '/repo-' . $$;
(undef, $error) = run_command( 'clone', '--from', 'sqlite://file://foo' );
is( $error, <<EOM
I couldn't determine a filesystem root from the given URL.
Correct syntax is (sqlite:)file:///replica/root .
EOM
, 'sqlite://file://foo errors out' );

$ENV{'PROPHET_REPO'} = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG}  ) . '/repo-' . $$;
(undef, $error)
    = run_command( 'clone', '--from', 'sqlite:http://www.example.com/sd' );
is( $error, <<EOM
I couldn't determine a filesystem root from the given URL.
Correct syntax is (sqlite:)file:///replica/root .
EOM
, 'SQLite replicas can\'t be via http' );

$ENV{'PROPHET_REPO'} = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG}  ) . '/repo-' . $$;
(undef, $error) = run_command( 'clone',
        '--from', 'prophet:http://web.mit.edu/spang/Public/tmp/bogus-sd' );
# Don't test fetch errors because the user running these tests may or may not
# have network, so they won't always be the same.
like( $error,
    qr{The source replica 'http://web.mit.edu/spang/Public/tmp/bogus-sd' doesn't exist or is unreadable.|Could not fetch http://},
    'prophet replicas *can* be via http',
);
