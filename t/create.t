use warnings;
use strict;
use Test::More 'no_plan';
use File::Temp qw'tempdir';

use_ok('SVN::PropDB::Handle');
my $REPO= tempdir(CLEANUP => 0).'/repo-'.$$;
ok(! -d $REPO);
`svnadmin create $REPO`;
ok(-d $REPO, "The repo exists ater svnadmin create");
my $cxn = SVN::PropDB::Handle->new( repository => "$REPO");
isa_ok($cxn, 'SVN::PropDB::Handle', "Got the cxn");
use_ok('SVN::PropDB::Record');
my $record = SVN::PropDB::Record->new(handle =>$cxn);
isa_ok($record, 'SVN::PropDB::Record');
my $uuid  = $record->create(props => { name => 'Jesse', age => 31});
ok($uuid);
is($record->get_prop(name => 'age'), 31);
$record->set_prop( name => 'age', value => 32);
is($record->get_prop(name => 'age'), 32);


1;
