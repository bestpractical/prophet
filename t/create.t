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
is($record->prop(name => 'age'), 31);
$record->set_prop( name => 'age', value => 32);
is($record->prop(name => 'age'), 32);

    my $kaia = $record->create(props => { name => 'Kaia', age => 24});
ok( $kaia);
my $mao = $record->create(props => { name => 'Mao', age => 0.7, species => 'cat'});
ok ($mao);
my $mei= $record->create(props => { name => 'Mei', age => "0.7", species => 'cat'});
ok ($mei);
use_ok('SVN::PropDB::Collection');

my $people = SVN::PropDB::Collection->new( handle => $cxn);
$people->matching(sub { (shift->prop(name => 'species')||'') ne 'cat'});
is($#{$people->as_array_ref}, 1);
my @people= @{$people->as_array_ref};
is_deeply([ sort map {$_->prop(name => 'name')} @people], [qw(Jesse Kaia)]);

my $cats = SVN::PropDB::Collection->new( handle => $cxn);
$cats->matching(sub { (shift->prop(name => 'species')||'') eq 'cat'});
is($#{$cats->as_array_ref}, 1);
my @cats= @{$cats->as_array_ref};
for (@cats) {
    is ($_->prop(name=>'age') , "0.7");
}
is_deeply([ sort map {$_->prop(name => 'name')} @cats], [qw(Mao Mei)]);

my $cat = SVN::PropDB::Record->new(handle => $cxn);
$cat->load(uuid => $mao);
$cat->set_prop(name => 'age', value => '0.8');
my $cat2 = SVN::PropDB::Record->new(handle => $cxn);
$cat2->load(uuid => $mei);
$cat2->set_prop(name => 'age', value => '0.8');

is($#{$cats->as_array_ref}, 1);
my @cats= @{$cats->as_array_ref};
for (@cats) {
    is ($_->prop(name=>'age') , "0.8");
}

1;
