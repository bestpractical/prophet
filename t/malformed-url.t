use warnings;
use strict;

use Test::More tests => 6;
use File::Temp qw(tempdir);
use Test::Script::Run qw(run_script);

$ENV{'PROPHET_REPO'} = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG}  ) . '/repo-' . $$;

# try to make prophet clone explode by feeding it bogus URLs

(undef, undef, my $error) = run_script( 'prophet', ['clone', '--from', 'malformed-url'] );
is( $error, <<EOM
I don't know how to handle the replica URL you provided - 'malformed-url'.
Is your syntax correct?
EOM
, 'malformed url errors out' );

$ENV{'PROPHET_REPO'} = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG}  ) . '/repo-' . $$;
(undef, undef, $error)
    = run_script( 'prophet', ['clone', '--from', 'sqlite:foo'] );
is( $error, <<EOM
I couldn't determine a filesystem root from the given URL.
Correct syntax is (sqlite:)file:///replica/root .
EOM
, 'sqlite:foo errors out' );

# sqlite is default replica type
$ENV{'PROPHET_REPO'} = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG}  ) . '/repo-' . $$;
(undef, undef, $error)
    = run_script( 'prophet', ['clone', '--from', 'file:foo'] );
is( $error, <<EOM
I couldn't determine a filesystem root from the given URL.
Correct syntax is (sqlite:)file:///replica/root .
EOM
, 'file:foo errors out' );

$ENV{'PROPHET_REPO'} = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG}  ) . '/repo-' . $$;
(undef, undef, $error)
    = run_script( 'prophet', ['clone', '--from', 'sqlite://file://foo'] );
is( $error, <<EOM
I couldn't determine a filesystem root from the given URL.
Correct syntax is (sqlite:)file:///replica/root .
EOM
, 'sqlite://file://foo errors out' );

$ENV{'PROPHET_REPO'} = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG}  ) . '/repo-' . $$;
(undef, undef, $error)
    = run_script( 'prophet',
        ['clone', '--from', 'sqlite:http://www.example.com/sd'] );
is( $error, <<EOM
I couldn't determine a filesystem root from the given URL.
Correct syntax is (sqlite:)file:///replica/root .
EOM
, 'SQLite replicas can\'t be via http' );

$ENV{'PROPHET_REPO'} = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG}  ) . '/repo-' . $$;
(undef, my $out, undef)
    = run_script( 'prophet',
        ['clone', '--from',
        'prophet:http://web.mit.edu/spang/Public/tmp/bogus-sd'] );
# Don't test fetch errors because the user running these tests may or may not
# have network, so they won't always be the same.
is( $out,
    "The source replica 'http://web.mit.edu/spang/Public/tmp/bogus-sd' doesn't exist or is unreadable.",
    'prophet replicas *can* be via http',
);
