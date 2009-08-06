package App::Settings::Test;
use warnings;
use strict;

use base qw(Prophet::Test Exporter);

use lib 't/Settings/lib';
use App::Settings::CLI;

our @EXPORT = qw/as_alice as_bob diag run_settings_command like ok
repo_uri_for/;

Prophet::Test->import;

# don't use Prophet::Test::run_command since we want our app to be
# App::Settings rather than Prophet::App
sub run_settings_command {
    my $output = '';
    my $error  = '';
    open my $out_handle, '>', \$output;

    # feed a persistent handle in to keep the prop cache between
    # commands (clear the handle's cache if something not using
    # this handle object changes props on disk; for example a
    # subprocess using run_output_matches and friends)
    App::Settings::CLI->new->invoke(
        $out_handle, \$error, @_,
    );

    return wantarray ? ($output, $error) : $output;
}

1;

