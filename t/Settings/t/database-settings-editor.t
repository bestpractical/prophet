#!/usr/bin/perl -w
use warnings;
use strict;

use lib 't/Settings/lib';

use App::Settings::Test tests => 9;
use Prophet::Util;
use File::Spec;
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
like( $out, qr/\Q$valid_settings_output\E/, "changed settings output matches" );

# test settings (interactive editing)

my $template;

# first set the editor to an editor script
Prophet::Test::set_editor( sub {
    my $content = shift;

    $template = $content;

    $content =~ s/(?<=^default_status: \[")new(?="\])/open/m; # valid json change
    $content =~ s/^default_milestone(?=: \["alpha"\])$/invalid_setting/m; # changes setting name
    $content =~ s/(?<=uuid: 6)C(?=BD84A1)/F/m; # changes a UUID to an invalid one
    $content =~ s/^project_name//m; # deletes setting

    return $content;
} );

# then edit the settings
# (can't use run_command with editor scripts because they don't play nicely
# with output redirection)
$out = run_command( 'settings', 'edit' );
is( $out, <<'END_OUTPUT', 'interactive settings edit' );
Changed default_status from ["new"] to ["open"].
Setting with uuid "6FBD84A1-4568-48E7-B90C-F1A5B7BD8ECD" does not exist.
END_OUTPUT

my $valid_template = Prophet::Util->slurp('t/data/settings-first.tmpl');
like( $template, qr/\Q$valid_template\E/,
        'interactive template was correct' );

# check the settings with settings --show
$valid_settings_output = Prophet::Util->slurp('t/data/settings-second.tmpl');

$out = run_command( qw/settings show/ );
like( $out, qr/\Q$valid_settings_output\E/, "changed settings output matches" );

# test setting to invalid json
Prophet::Test::set_editor( sub {
    my $content = shift;

    $template = $content;

    $content =~ s/(?<=^default_component: \[")core(?="\])/ui/m; # valid json change
    $content =~ s/(?<=^default_milestone: \["alpha")]$//m; # invalid json

    return $content;
} );

$out = run_command( 'settings', 'edit' );
like( $out, qr/^An error occured setting default_milestone to \["alpha":.*?
Changed default_component from \["core"\] to \["ui"\]./m,
    'interactive settings edit with JSON error' );

$valid_template = Prophet::Util->slurp('t/data/settings-second.tmpl');
like( $template, qr/\Q$valid_template\E/, 'interactive template was correct');

# check the settings with settings show
$valid_settings_output = Prophet::Util->slurp('t/data/settings-third.tmpl');

$out = run_command( qw/settings show/ );
like( $out, qr/\Q$valid_settings_output\E/, 'changed settings output matches' );
