#!/usr/bin/perl 
#
use warnings;
use strict;

use Prophet::Test tests => 20;

as_alice {
    run_ok('prophet-node-create', [qw(--type Bug --status new --from alice )], "Created a record as alice"); 
    run_output_matches('prophet-node-search', [qw(--type Bug --regex .)], [qr/new/], " Found our record");
    };


diag('Bob syncs from alice');

my $record_id;

as_bob {

    run_ok('prophet-node-create', [qw(--type Dummy --ignore yes)], "Created a dummy record"); 
  
    run_ok('prophet-merge', ['--to', repo_uri_for('bob'), '--from', repo_uri_for('alice')], "Sync ran ok!");
    # check our local replicas
   my  ($ret, $out, $err) = run_script('prophet-node-search', [qw(--type Bug --regex .)]);
    like($out, qr/new/, "We have the one node from alice") ;
    if ($out =~ /^(.*?)\s./) {
        $record_id = $1;
    }
    diag($record_id);

    run_ok('prophet-node-update', ['--type','Bug','--uuid',$record_id, '--status' => 'stalled']);
    run_output_matches('prophet-node-show', ['--type', 'Bug', '--uuid', $record_id],
                       ['id: '.$record_id, 'status: stalled', 'from: alice'],
                       'content is correct');
};

as_alice {
    run_ok('prophet-node-update', ['--type','Bug','--uuid',$record_id, '--status' => 'stalled']);
    run_output_matches('prophet-node-show', ['--type', 'Bug', '--uuid', $record_id],
                       ['id: '.$record_id, 'status: stalled', 'from: alice'],
                       'content is correct');

};

# This conflict, we can autoresolve

as_bob {
    # XXX TODO: this should actually fail right now.
    # in perl code, we're going to run the merge (just as prophet-merge does)
    
    use_ok('Prophet::Sync::Source::SVN'   );
    
    my $source = Prophet::Sync::Source->new( { url => repo_uri_for('alice') } );
    my $target = Prophet::Sync::Source->new( { url => repo_uri_for('bob')} );

    eval {
    $target->import_changesets( from => $source , conflict_callback=> sub { 
    
    my $conflict_obj = shift;
    isa_ok($conflict_obj, 'Prophet::Conflict');

    my @conflicting_changes = @{$conflict_obj->conflicting_changes};
    is($#conflicting_changes, 0, "Only one conflicting change");
    my $change = shift @conflicting_changes;
    isa_ok($change, 'Prophet::ConflictingChange');
    is($change->change_type, 'update_file');
    my @prop_conflicts = @{$change->prop_conflicts};
    is($#prop_conflicts, 0, "Found one prop conflict");
    my $c = shift @prop_conflicts;
    isa_ok($c, 'Prophet::ConflictingPropChange');
    is($c->name, 'status');
    is($c->source_old_value, 'new');
    is($c->source_new_value,'stalled');
    is($c->target_value,'stalled');
    die;

 });
    }; 
    # Throw away the return. we wanted to inspect the conflict but not apply anything





    # at the first sign of conflict, we're going to call back to a routine we inject to see if the conflict object is as we expect it
    # Then we'll inject a hard-coded resolution into the conflict object
    # then we'll let the code finish applying it.
    # Then we'll check that bob's current state is right and that bob has a merge-ticket from alice


};


