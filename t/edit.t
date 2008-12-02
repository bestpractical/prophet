use warnings;
use strict;
use Prophet::Test tests => 34;
use File::Temp qw'tempdir';

$ENV{'PROPHET_REPO'} = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG}  ) . '/repo-' . $$;
my $prophet = Prophet::CLI->new;
$prophet->handle->initialize;

my ($luid,  $uuid);
my $created_re = qr/Created Robot Master (\d+)(?{ $luid = $1}) \((\S+)(?{ $uuid = $2 })\)/;
my $updated_re = qr/Robot Master \d+ \((\S+)(?{ $uuid = $1 })\) updated/;
my $invoked_editor = 0;

# ------------

my $out = run_command('create', '--type=Robot Master');
like($out, $created_re);
is($invoked_editor, 0, "Editor not invoked");
ok($uuid, "got a uuid");
cleanup();

# ------------

$out = run_command('create', '--type=Robot Master', '--edit');
# $out only captures STDOUT, not STDERR
is($out, '', 'Create aborted on no editor input');
is($invoked_editor, 1, "Editor invoked once");
cleanup();

# ------------

editor(sub {
    return << "TEXT";
name: Shadow Man
weapon: Shadow Blade
weakness: Top Spin
strength: 
TEXT
});

$out = run_command('create', '--type=Robot Master', '--edit');
like($out, $created_re);
is($invoked_editor, 1, "Editor invoked once");
ok($uuid, "got a uuid");
my $shadow_man = load_record('Robot Master', $uuid);
is($shadow_man->uuid, $uuid, "correct uuid");
is($shadow_man->prop('name'), 'Shadow Man', 'correct name');
is($shadow_man->prop('weapon'), 'Shadow Blade', 'correct weapon');
is($shadow_man->prop('weakness'), 'Top Spin', 'correct weakness');
is($shadow_man->prop('strength'), undef, 'strength not set');
cleanup();

# ------------

editor(sub {
    return << "TEXT";
# called Clash Man in Japan
name: Crash Man

# also called Clash Bomb in Japan
weapon: Crash Bomb

# in Mega Man 3, he's weak to Hard Knuckle
weakness: Air Shooter
TEXT
});

$out = run_command('create', '--type=Robot Master', '--edit');
like($out, $created_re);
is($invoked_editor, 1, "Editor invoked once");
ok($uuid, "got a uuid");
my $crash_man = load_record('Robot Master', $uuid);
is($crash_man->uuid, $uuid, "correct uuid");
is($crash_man->prop('name'), 'Crash Man', 'correct name');
is($crash_man->prop('weapon'), 'Crash Bomb', 'correct weapon');
is($crash_man->prop('weakness'), 'Air Shooter', 'correct weakness');
cleanup();

# ------------

editor(sub {
    return << "TEXT";
name: Clash Man
weapon: Clash Bomb
TEXT
});

$out = run_command(
    'update',
    '--type=Robot Master',
    '--uuid=' . $crash_man->uuid,
    '--edit',
);

like($out, $updated_re);
is($invoked_editor, 1, "Editor invoked once");
ok($uuid, "got a uuid");
my $crash_man2 = load_record('Robot Master', $uuid);
is($crash_man2->uuid, $uuid, "correct uuid");
is($crash_man2->prop('name'), 'Clash Man', 'corrected name');
is($crash_man2->prop('weapon'), 'Clash Bomb', 'corrected weapon');
is($crash_man2->prop('weakness'), undef, 'weakness deleted');
cleanup();

# ------------

$out = run_command(
    'update',
    '--type=Robot Master',
    '--uuid=' . $crash_man->uuid,
    '--',
    '--weakness=Hard Knuckle',
);

like($out, $updated_re);
is($invoked_editor, 0, "Editor not invoked");
ok($uuid, "got a uuid");
my $crash_man3 = load_record('Robot Master', $uuid);
is($crash_man3->uuid, $uuid, "correct uuid");
is($crash_man3->prop('name'), 'Clash Man', 'same name');
is($crash_man3->prop('weapon'), 'Clash Bomb', 'same weapon');
is($crash_man3->prop('weakness'), 'Hard Knuckle', 'updated weakness');
cleanup();

# ------------

sub cleanup {
    undef $uuid;
    $invoked_editor = 0;
    editor(sub { '' });
}

sub editor {
    my $code = shift;
    set_editor(sub {
        $invoked_editor++;
        $code->(@_);
    });
}
