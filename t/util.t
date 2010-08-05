use warnings;
use strict;
use Prophet::Test tests => 9;
use_ok('Prophet::Util');
use File::Temp 'tempdir';
use File::Path;
use File::Spec;
use Cwd;
my $base = Cwd::abs_path( tempdir( CLEANUP => 1 ) );
mkpath( File::Spec->catdir($base, 'foo', 'bar', 'baz', 'foo' ) ) or die $!; 

my %updir = (

    # 0 here means no depth arg, should act as depth 1
    0 => {
        'foo/bar/baz/foo'  => 'foo/bar/baz',
        'foo/bar/baz/foo/' => 'foo/bar/baz',
    },
    1 => {
        'foo/bar/baz/foo'  => 'foo/bar/baz',
        'foo/bar/baz/foo/' => 'foo/bar/baz',
    },
    2 => {
        'foo/bar/baz/foo'  => 'foo/bar',
        'foo/bar/baz/foo/' => 'foo/bar',
    },
    3 => {
        'foo/bar/baz/foo'  => 'foo',
        'foo/bar/baz/foo/' => 'foo',
    }
);

for my $depth ( keys %updir ) {
    for my $path ( keys %{ $updir{$depth} } ) {
        my $value = join '/', $base, $updir{$depth}{$path};
        $path = join '/', $base, $path;
        is( Prophet::Util->updir($path, $depth || () ),
            $value, "updir of $path with depth $depth is $value" );
    }
}

