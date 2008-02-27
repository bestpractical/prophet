#!/usr/bin/perl -w

use Test::More tests => 7;
use File::Temp qw(tempdir);
use File::Path qw(rmtree);
use strict;
use YAML;
use SVN::Core;
use SVN::Ra;
use SVN::Delta;
my $uri = "file:///Users/jesse/svk/SVN-PropDB/t/samples/createt";
my $ra = SVN::Ra->new( url => $uri);
isa_ok ($ra, 'SVN::Ra');
ok ($ra->get_uuid, $ra->get_uuid);
is ($ra->get_latest_revnum, 11);
for(1..11)  {
diag(YAML::Dump($ra->rev_proplist($_)));
#my $reporter = $ra->do_diff (1, '', 1, SVN::Delta::Editor->new);
    my (undef, undef, $prop) = eval { $ra->get_dir ('', -1) };
warn YAML::Dump($prop);
#isa_ok ($reporter, 'SVN::Ra::Reporter');

}
#is ($ra->get_latest_revnum, 0);

