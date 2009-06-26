use warnings;
use strict;
use Prophet::Test tests => 44;
use Test::Exception;

use File::Temp qw'tempdir';

# test coverage for Prophet::CLI::CLIContext arg parsing (parse_args,
# set_type_and_uuid, setup_from_args)

use_ok('Prophet::CLI');
$ENV{'PROPHET_REPO'} = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG}  ) . '/repo-' . $$;

my $cli = Prophet::CLI->new();
my $cxn = $cli->handle;
my $app = $cli->app_handle;
isa_ok( $cxn, 'Prophet::Replica', "Got the cxn" );

$cxn->initialize;

my $context = $cli->context;

# create a record so we have a valid uuid/luid to test
# set_type_and_uuid with
use_ok('Prophet::Record');
my $record = Prophet::Record->new( handle => $cxn, type => 'Person' );
my $mao = $record->create( props => { name => 'Mao', age => 0.7, species => 'cat' } );
my $uuid = $record->uuid;
my $luid = $record->luid;

sub reset_context {
    my $context = shift;

    $context->clear_args;
    $context->clear_props;
    $context->type('reset');
    $context->uuid('reset');
    $context->primary_commands([]);
    $context->prop_set([]);
}

diag('set_type_and_uuid testing');

diag('setting type with an arg, uuid with luid in luid arg');
$context->set_arg( type => 'bug');
$context->set_arg( luid => $luid );
$context->set_type_and_uuid;
is($context->uuid, $uuid, 'uuid is correct');
is($context->type, 'bug', 'type is correct');
reset_context($context);

diag('setting type with primary command, uuid with luid in id arg');
$context->primary_commands( [ 'bug', 'search' ] );
$context->set_arg( id => $luid );
$context->set_type_and_uuid;
is($context->uuid, $uuid, 'uuid is correct');
is($context->type, 'bug', 'type is correct');
reset_context($context);

diag('set uuid with uuid in id arg');
$context->set_arg( id => $uuid );
$context->set_arg( type => 'bug' ); # so it doesn't explode
$context->set_type_and_uuid;
is($context->uuid, $uuid, 'uuid is correct');
reset_context($context);

diag('set uuid with uuid in uuid arg');
$context->set_arg( uuid => $uuid );
$context->set_arg( type => 'bug' ); # so it doesn't explode
$context->set_type_and_uuid;
is($context->uuid, $uuid, 'uuid is correct');
reset_context($context);

diag('parse_args testing');

diag('primary commands only');
$context->parse_args(qw(search));
is_deeply($context->primary_commands, [ 'search' ], 'primary commands are correct');
is($context->arg_names, 0, 'no args were set');
is($context->prop_names, 0, 'no props were set');
reset_context($context);

diag('primary commands + args with no values');
$context->parse_args(qw(show --verbose --test));
is_deeply($context->primary_commands, [ 'show' ], 'primary commands are correct');
is($context->arg('verbose'), undef, 'verbose arg set correctly');
is($context->arg('test'), undef, 'test arg set correctly');
reset_context($context);

diag('primary commands + mixed args with vals and not');
$context->parse_args(qw(show --test bar --zap));
is_deeply($context->primary_commands, [ 'show' ], 'primary commands are correct');
is($context->arg('zap'), undef, 'zap arg set correctly');
is($context->arg('test'),'bar', 'test arg set correctly');
reset_context($context);

diag('primary commands + mixed args with vals and not (swapped)');
$context->parse_args(qw(show --test --zap bar));
is_deeply($context->primary_commands, [ 'show' ], 'primary commands are correct');
is($context->arg('zap'), 'bar', 'zap arg set correctly');
is($context->arg('test'), undef, 'test arg set correctly');
reset_context($context);

diag('primary commands + multiple args with vals');
$context->parse_args(qw(show --test bar --zap baz));
is_deeply($context->primary_commands, [ 'show' ], 'primary commands are correct');
is($context->arg('zap'), 'baz', 'zap arg set correctly');
is($context->arg('test'), 'bar', 'test arg set correctly');
reset_context($context);

diag('primary commands + props only');
$context->parse_args(qw(update -- name=Larry species beatle));
is_deeply($context->primary_commands, [ 'update' ], 'primary commands are correct');
is($context->prop('name'), 'Larry', 'name prop set correctly');
is($context->prop('species'), 'beatle', 'species prop set correctly');
# now check the prop set to check comparators
is_deeply($context->prop_set->[0], { prop => 'name', cmp => '=', value =>
        'Larry' }, 'name has correct comparator');
# if there is no comparator given it defaults to =
is_deeply($context->prop_set->[1], { prop => 'species', cmp => '=', value =>
        'beatle' }, 'species has correct comparator');
reset_context($context);

diag('primary commands + props only (check that comparators are grabbed correctly)');

# removed colour<> red as we don't support not having a space between the
# prop end and the comparator if there's a space after it
$context->parse_args(qw(update -- legs!=8 eyes ne 2 spots =~0));
is_deeply($context->primary_commands, [ 'update' ], 'primary commands are correct');
is($context->prop('legs'), '8', 'legs prop set correctly');
is($context->prop('eyes'), '2', 'eyes prop set correctly');
# is($context->prop('colour'), 'red', 'colour prop set correctly');
is($context->prop('spots'), '0', 'spots prop set correctly');
# now check the prop set to check comparators
is_deeply($context->prop_set->[0], { prop => 'legs', cmp => '!=', value =>
        '8' }, 'legs has correct comparator');
is_deeply($context->prop_set->[1], { prop => 'eyes', cmp => 'ne', value =>
        '2' }, 'eyes has correct comparator');
is_deeply($context->prop_set->[2], { prop => 'spots', cmp => '=~', value =>
        '0' }, 'spots has correct comparator');
# is_deeply($context->prop_set->[3], { prop => 'colour', cmp => '<>', value =>
#         'red' }, 'colour has correct comparator');
reset_context($context);

diag('args and props and check --props... the -- should trigger new props with undef values');
$context->parse_args(qw(update --verbose --props --name --Curly));
is_deeply($context->primary_commands, [ 'update' ], 'primary commands are correct');
is($context->arg('verbose'), undef, 'verbose arg set correctly');
is($context->prop('name'), undef, 'name prop set correctly');
is($context->prop('Curly'), undef, 'Curly prop set correctly');
reset_context($context);

diag('errors');

# "10 doesn't look like --argument"
dies_ok(sub { $context->parse_args(qw(show --verbose update 10)) }, 'dies on parse error');
reset_context($context);

# XXX other errors?

diag('put it all together with setup_from_args');
$context->setup_from_args( 'bug', 'show', '--id', $luid );
is_deeply($context->primary_commands, [ 'bug', 'show' ],
    'primary commands are correct');
is($context->uuid, $uuid, 'uuid is correct');
is($context->type, 'bug', 'type is correct');
reset_context($context);
