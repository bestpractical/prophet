#!/usr/bin/perl -w
use warnings;
use strict;

use lib 't/Settings/lib';

use App::Settings::Test tests => 9;
use Prophet::Util;
use File::Spec;
use Test::Script::Run;
no warnings 'once';

# test the CLI and interactive UIs for showing and updating settings

BEGIN {
    $ENV{'PROPHET_REPO'} = $Prophet::Test::REPO_BASE . '/_svb';
    diag $ENV{'PROPHET_REPO'};
}

my $out = run_command( 'init' );
is( $out, "Initialized your new Prophet database.\n", 'replica init' );

# test noninteractive set
$out = run_command(
    'settings', 'set', '--', 'statuses', '["new","open","stalled"]',
);
my $expected = <<'END_OUTPUT';
Trying to change statuses from ["new","open","stalled","closed"] to ["new","open","stalled"].
 -> Changed.
END_OUTPUT
is( $out, $expected, "settings set went ok" );

# check with settings show
my $valid_settings_output = Prophet::Util->slurp('t/data/settings-first.tmpl');

$out = run_command( qw/settings/ );
is( $out, $valid_settings_output, "changed settings output matches" );

# test settings (interactive editing)

my $filename = File::Temp->new(
    TEMPLATE => File::Spec->catfile(File::Spec->tmpdir(), '/statusXXXXX') )->filename;
diag ("interactive template status will be found in $filename");
# first set the editor to an editor script
Prophet::Test->set_editor_script("settings-editor.pl --first $filename");

# then edit the settings
# (can't use run_command with editor scripts because they don't play nicely
# with output redirection)
run_output_matches( 'settings', [ 'settings', 'edit' ],
    [
        'Changed default_status from ["new"] to ["open"].',
        'Setting with uuid "6FBD84A1-4568-48E7-B90C-F1A5B7BD8ECD" does not exist.',
    ], [], "interactive settings set went ok",);


# check the tempfile to see if the template presented to the editor was correct
chomp(my $template_ok = Prophet::Util->slurp($filename));
is($template_ok, 'ok!', "interactive template was correct");

# check the settings with settings --show
$valid_settings_output = Prophet::Util->slurp('t/data/settings-second.tmpl');

# look up db uuid and clear the prop cache, since we've modified the
# on-disk props via another process
my ($replica_uuid) = replica_uuid();
Prophet::Replica::sqlite::clear_prop_cache( $replica_uuid );

$out = run_command( qw/settings show/ );
is( $out, $valid_settings_output, "changed settings output matches" );

# test setting to invalid json
my $second_filename = File::Temp->new(
    TEMPLATE => File::Spec->catfile(File::Spec->tmpdir(), '/statusXXXXX') )->filename;
diag ("interactive template status will be found in $second_filename");
Prophet::Test->set_editor_script("settings-editor.pl --second $second_filename");
run_output_matches( 'settings', [ 'settings', 'edit' ],
    [
        qr/^An error occured setting default_milestone to \["alpha":/,
        'Changed default_component from ["core"] to ["ui"].',
    ], [], "interactive settings set with JSON error went ok",
);

Prophet::Replica::sqlite::clear_prop_cache( $replica_uuid );

# check the tempfile to see if the template presented to the editor was correct
chomp($template_ok = Prophet::Util->slurp($filename));
is($template_ok, 'ok!', "interactive template was correct");

# check the settings with settings show
$valid_settings_output = Prophet::Util->slurp('t/data/settings-third.tmpl');

# run_command( 'settings' );
$out = run_command( qw/settings show/ );
is( $out, $valid_settings_output, 'changed settings output matches' );
