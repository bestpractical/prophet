#!/usr/bin/perl 
#
use warnings;
use strict;
use Prophet::Test tests => 68;
use File::Temp qw/tempfile/;
use Test::Script::Run;

( my $_fh, $ENV{'PROPHET_APP_CONFIG'} ) = tempfile(UNLINK => !$ENV{PROPHET_DEBUG});
close $_fh; # or windows will cry :/
diag("Using config file $ENV{PROPHET_APP_CONFIG}");

use_ok('Prophet::CLI');

my $a = Prophet::CLI->new();
can_ok($a, 'app_handle');
can_ok($a->app_handle, 'config');
my $config = $a->config;
$config->load;

is_deeply( scalar $config->aliases, {}, 'initial alias is empty' );

# no news is good news
my @cmds = (
    {
        cmd     => [ 'show' ],
        output  => qr/No aliases for the current repository/,
        comment => 'show empty aliases',
    },
    {
        cmd     => [ 'add', 'pull -a=pull --all' ],
        comment => 'add a new alias',
        # no output specified = no output expected
    },
    {
        cmd     => [ 'pull -a' ],
        output  => qr/pull --all/,
        comment => 'new alias set correctly',
    },
    {
        # this alias is bad, please don't use it in real life
        cmd     => [ 'set', 'pull -a=pull --local' ],
        comment =>
          q{changed alias 'pull -a' from 'pull --all' to 'pull --local'},
    },
    {
        cmd     => [ 'pull -a' ],
        output  => qr/pull --local/,
        comment => 'alias changed correctly',
    },
    {
        cmd     => [ 'delete', 'pull -a' ],
        comment => q{deleted alias 'pull -a = pull --local'},
    },
    {
        cmd     => [ 'delete', 'pull -a' ],
        error   => qr/No occurrence of alias.pull -a found to unset/,
        comment => q{delete an alias that doesn't exist any more},
    },
    {
        cmd     => [ 'add', 'pull -a=pull --all' ],
        comment => 'add a new alias',
    },
    {
        cmd     => [ 'pull -a' ],
        output  => qr/pull --all/,
        comment => 'alias is set correctly',
    },
    {
        cmd     => [ 'add', 'pull -l=pull --local' ],
        comment => 'add a new alias',
    },
    {
        cmd     => [ 'pull -l' ],
        output  => qr/pull --local/,
        comment => 'alias is set correctly',
    },
    {
        cmd     => [ 'show' ],
        output  => 
            qr/Active aliases for the current repository \(including user-wide and global\naliases if not overridden\):\n\npull -l = pull --local\npull -a = pull --all/,
        comment => 'show',
    },
    {
        cmd     => [ 'add', 'foo', 'bar', '=', 'bar',  'baz' ],
        comment => 'added alias foo bar',
    },
    {
        cmd     => [ 'foo bar' ],
        output  => qr/bar baz/,
        comment => 'alias is set correctly',
    },
    {
        cmd     => [ 'foo', 'bar', '=bar',  'baz' ],
        comment => 'set alias foo bar again',
    },
    {
        cmd     => [ 'foo', 'bar=', 'bar',  'baz' ],
        comment => 'set alias with tail =',
    },
    {
        cmd => [ 'foo bar' ],
        output  => qr/bar baz/,
        comment => 'alias foo bar still the same',
    },
    {
        cmd     => [ 'delete', 'foo', 'bar' ],
        comment => 'deleted alias foo bar',
    },
    {
        cmd     => [ 'foo', 'bar' ],
        comment => 'deleted alias no longer exists',
    },
    {
        cmd     => [ 'set', 'foo bar', '=', 'bar baz'],
        comment => 'set alias again with different syntax',
    },
    # tests for alternate syntax
    {
        cmd     => [ 'foo bar', 'bar baz'],
        comment => 'alias foo bar = bar baz didn\'t change',
    },
    {
        cmd     => [ 'foo', 'bar baz'],
        comment => 'added alias foo',
    },
    {
        cmd     => [ 'foo' ],
        output  => qr/bar baz/,
        comment => 'alias foo set correctly',
    },
    {
        cmd     => [ 'foo bar', 'bar'],
        comment => 'changed alias foo bar',
    },
    {
        cmd     => [ 'pull --from http://www.example.com/', 'pfe'],
        comment => 'added alias with weird characters',
    },
    {
        cmd     => [ 'pull --from http://www.example.com/'],
        output  => qr/pfe/,
        comment => 'alias with weird chars is correct',
    },
    # test cases for syntax error messages
    {
        cmd     => [ 'add' ],
        error   => qr/^usage: aliases.t aliases add "alias text" "cmd to translate to"$/,
        comment => 'add usage msg is correct',
    },
    {
        cmd     => [ 'delete' ],
        error   => qr/^usage: aliases.t aliases delete "alias text"$/,
        comment => 'delete usage msg is correct',
    },
    # test warning when accidentally setting args
    {
        cmd     => [ 'pt', '=', 'push', '--to', 'foo@example.com' ],
        output  =>
            qr|W: You have args set that aren't used by this command! Quote your\nW: key/value if this was accidental.\nW: - offending args: to\nW: - running command with key 'alias.pt', value 'push'|,
            comment => 'warning when setting accidental arg',
    },
    {
        cmd     => [ 'delete', 'pt' ],
        comment => 'delete previous bad alias',
    },
);

for my $item ( @cmds ) {
    my $exp_output = defined $item->{output} ? $item->{output} : qr/^$/;
    my $exp_error = defined $item->{error} ? $item->{error} : qr/^$/;

    my ($got_output, $got_error)
        = run_command( 'aliases', @{$item->{cmd}} );

    like( $got_output, $exp_output, $item->{comment} . ' (STDOUT)' );
    like( $got_error, $exp_error, $item->{comment} . ' (STDERR)' );
}

# check aliases in config
my $aliases = Prophet::Config->new(
    app_handle => Prophet::CLI->new->app_handle,
    confname => 'testrc'
)->aliases;

is_deeply(
    $aliases,
    {
        'pull -l' => 'pull --local',
        'pull -a' => 'pull --all',
        'foo bar' => 'bar',
        'foo' => 'bar baz',
        'pull --from http://www.example.com/' => 'pfe',
    },
    'non empty aliases',
);

# check content in config
my $content;
open my $fh, '<', $ENV{'PROPHET_APP_CONFIG'} or die "failed to open $ENV{'PROPHET_APP_CONFIG'}: $!";
{ local $/; $content = <$fh>; }
is( $content, <<EOF, 'content in config' );

[core]
	config-format-version = 0
[alias]
	pull -a = pull --all
	pull -l = pull --local
	foo = bar baz
	foo bar = bar
	pull --from http://www.example.com/ = pfe
EOF

# tests for interactive alias editing
my $filename = File::Temp->new(
    TEMPLATE => File::Spec->catfile(File::Spec->tmpdir(), '/statusXXXXX') )->filename;
diag ("interactive template status will be found in $filename");
Prophet::Test->set_editor_script("aliases-editor.pl --first $filename");

# can't run this with run_command because STDOUT redirection will
# screw up piping to the script
run_output_matches( 'prophet', [ 'aliases', 'edit' ],
    [
        "Added alias 'something different' = 'pull --local'",
        "Changed alias 'foo' from 'bar baz'to 'sigh'",
        "Deleted alias 'pull -l'",
    ], [], 'aliases edit went ok',
);

# check with alias show
my $valid_settings_output = Prophet::Util->slurp('t/data/aliases.tmpl');

my $got_output = run_command( 'alias', 'show' );
is( $got_output, $valid_settings_output, 'changed alias output matches' );
