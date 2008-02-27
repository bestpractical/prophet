use warnings;
use strict;
use Test::More 'no_plan';
use File::Temp qw'tempdir';

use_ok('Prophet::Handle');
my $REPO= tempdir(CLEANUP => 0).'/repo-'.$$;
ok(! -d $REPO);
diag ($REPO);
`svnadmin create $REPO`;
ok(-d $REPO, "The repo exists ater svnadmin create");
my $cxn = Prophet::Handle->new( repository => "$REPO", db_root => '/_propdb-test');
isa_ok($cxn, 'Prophet::Handle', "Got the cxn");
use_ok('Prophet::Record');
my $record = Prophet::Record->new(handle =>$cxn, type => 'Person');
isa_ok($record, 'Prophet::Record');
my $uuid  = $record->create(props => { name => 'Jesse', age => 31});
ok($uuid);
is($record->prop('age'), 31);
$record->set_prop( name => 'age', value => 32);
is($record->prop('age'), 32);

    my $kaia = $record->create(props => { name => 'Kaia', age => 24});
ok( $kaia);
my $mao = $record->create(props => { name => 'Mao', age => 0.7, species => 'cat'});
ok ($mao);
my $mei= $record->create(props => { name => 'Mei', age => "0.7", species => 'cat'});
ok ($mei);
use_ok('Prophet::Collection');

my $people = Prophet::Collection->new( handle => $cxn, type => 'Person');
$people->matching(sub { (shift->prop( 'species')||'') ne 'cat'});
is($#{$people->as_array_ref}, 1);
my @people= @{$people->as_array_ref};
is_deeply([ sort map {$_->prop('name')} @people], [qw(Jesse Kaia)]);

my $cats = Prophet::Collection->new( handle => $cxn, type => 'Person');
$cats->matching(sub { (shift->prop( 'species')||'') eq 'cat'});
is($#{$cats->as_array_ref}, 1);
my @cats= @{$cats->as_array_ref};
for (@cats) {
    is ($_->prop('age') , "0.7");
}
is_deeply([ sort map {$_->prop('name')} @cats], [qw(Mao Mei)]);

my $cat = Prophet::Record->new(handle => $cxn, type => 'Person');
$cat->load(uuid => $mao);
$cat->set_prop(name => 'age', value => '0.8');
my $cat2 = Prophet::Record->new(handle => $cxn, type => 'Person');
$cat2->load(uuid => $mei);
$cat2->set_prop(name => 'age', value => '0.8');

is($#{$cats->as_array_ref}, 1);
for (@cats) {
    is ($_->prop('age') , "0.8");
}

for (@cats) {
    ok ($_->delete);
}


my $records = Prophet::Collection->new(type => 'Person', handle => $cxn);
$records->matching(sub {1});
is($#{$records->as_array_ref} , 1);





1;
