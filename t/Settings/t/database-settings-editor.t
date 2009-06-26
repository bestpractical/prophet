#!/usr/bin/perl -w

use strict;

use Prophet::Test tests => 9;
use Prophet::Util;
use File::Temp qw(tempdir);
use File::Spec;
no warnings 'once';

$ENV{'PERL5LIB'} .=  ':t/Settings/lib';

# test the CLI and interactive UIs for showing and updating settings

BEGIN {
    require File::Temp;
    $ENV{'PROPHET_REPO'} = File::Temp::tempdir( CLEANUP => 1 ) . '/_svb';
    diag $ENV{'PROPHET_REPO'};
}

run_ok( 'settings', [ 'init' ] );

my $replica_uuid = replica_uuid;

# test noninteractive set
run_output_matches( 'settings', [ 'settings', '--set', '--', 'statuses',
    '["new","open","stalled"]' ],
    [
        'Trying to change statuses from ["new","open","stalled","closed"] to ["new","open","stalled"].',
        ' -> Changed.',
    ], [], "settings --set went ok",
);

# check with settings --show
my @valid_settings_output = Prophet::Util->slurp('t/data/settings-first.tmpl');
chomp (@valid_settings_output);

run_output_matches(
    'settings',
    [ qw/settings --show/ ],
    [ @valid_settings_output ], [], "changed settings output matches"
);

# test settings (interactive editing)

my $filename = File::Temp->new(
    TEMPLATE => File::Spec->catfile(File::Spec->tmpdir(), '/statusXXXXX') )->filename;
diag ("interactive template status will be found in $filename");
# first set the editor to an editor script
Prophet::Test->set_editor_script("settings-editor.pl --first $filename");

# then edit the settings
run_output_matches( 'settings', [ 'settings' ],
    [
        'Changed default_status from ["new"] to ["open"].',
        'Setting with uuid "6FBD84A1-4568-48E7-B90C-F1A5B7BD8ECD" does not exist.',
    ], [], "interactive settings set went ok",);

# check the tempfile to see if the template presented to the editor was correct
chomp(my $template_ok = Prophet::Util->slurp($filename));
is($template_ok, 'ok!', "interactive template was correct");

# check the settings with settings --show
@valid_settings_output = Prophet::Util->slurp('t/data/settings-second.tmpl');
chomp (@valid_settings_output);

run_output_matches(
    'settings',
    [ qw/settings --show/ ],
    [ @valid_settings_output ], [], "changed settings output matches"
);

# test setting to invalid json
my $second_filename = File::Temp->new(
    TEMPLATE => File::Spec->catfile(File::Spec->tmpdir(), '/statusXXXXX') )->filename;
diag ("interactive template status will be found in $second_filename");
Prophet::Test->set_editor_script("settings-editor.pl --second $second_filename");
run_output_matches( 'settings', [ 'settings' ],
    [
        qr/^An error occured setting default_milestone to \["alpha":/,
        'Changed default_component from ["core"] to ["ui"].',
    ], [], "interactive settings set with JSON error went ok",
);

# check the tempfile to see if the template presented to the editor was correct
chomp($template_ok = Prophet::Util->slurp($filename));
is($template_ok, 'ok!', "interactive template was correct");

# check the settings with settings --show
@valid_settings_output = Prophet::Util->slurp('t/data/settings-third.tmpl');
chomp (@valid_settings_output);

run_output_matches(
    'settings',
    [ qw/settings --show/ ],
    [ @valid_settings_output ], [], "changed settings output matches"
);
