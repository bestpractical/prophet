package App::Settings::Test;
use Prophet::Util;
use warnings;
use strict;

use base qw(Prophet::Test Exporter);

use lib 't/Settings/lib';
use App::Settings::CLI;

our @EXPORT = qw/as_alice as_bob diag run_command like ok
repo_uri_for replica_uuid/;

Prophet::Test->import;

$Prophet::Test::CLI_CLASS = 'App::Settings::CLI';

1;

