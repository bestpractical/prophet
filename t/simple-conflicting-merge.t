#!/usr/bin/perl 
#
use warnings;
use strict;

use Prophet::Test tests => 45;

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

    my $conflict_obj;

my $repo = repo_uri_for('bob');
diag `svn log -v $repo`;

    eval {
        $target->import_changesets(
            from              => $source,
            conflict_callback => sub {
                $conflict_obj = shift;
            }
        );
    };
#    warn $@;
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

    # Check to see if the nullification changeset worked out ok
    my $nullification = $conflict_obj->nullification_changeset;

    isa_ok($nullification, "Prophet::ChangeSet");
    ok($nullification->is_nullification);
    my @reverts = $nullification->changes;
    is($#reverts, 0, "Found one change");
    my $revert = shift @reverts;
    is($revert->change_type, 'update_file');
    my @prop_changes = $revert->prop_changes;
    is ( $#prop_changes, 0, "Found one prop change");
    is ($prop_changes[0]->name, 'status');
    is($prop_changes[0]->old_value, 'stalled');
    is($prop_changes[0]->new_value, 'new');
    
    
    # replay the last two changesets for bob's replica
    my @changesets = @{$target->fetch_changesets( after => ($target->prophet_handle->repo_handle->fs->youngest_rev - 2))};
    {
       # is the second most recent change:
       my $null_candidate  = shift @changesets;
        # - a nullification changeset

       ok($null_candidate->is_nullification, "It was marked as a nullification");
       my @changes = $null_candidate->changes;
        # - with one update-file
        is ($#changes,0, "The nullification only changed one prop");
        my $null_change = shift @changes;
        my @prop_changes =  $null_change->prop_changes;
        is($#prop_changes, 0, "one prop change");
        my $prop_change = shift @prop_changes;
        #  status: stalled->new
        is($prop_change->name, 'status');
        is($prop_change->old_value, 'stalled');
        is($prop_change->new_value, 'new');
    }
    
    
    # is the most recent change:
    {
        my $from_alice = shift @changesets;
        my @changes = $from_alice->changes;
        is ($#changes, 1, "Found 2 changes");
        
        
            my ($data_change) = grep { $_->node_type eq 'Bug'} @changes;
        is($data_change->change_type , 'update_file');
        my @prop_changes = $data_change->prop_changes;
        is($#prop_changes, 0, "only one prop changed");
        
        my $prop_change = shift @prop_changes;
        is($prop_change->name, 'status');
        is($prop_change->old_value, 'new');
        is($prop_change->new_value, 'stalled');

     #   update-file
    #      status new->stalled
    
    #  update-file
    my($mergeticket_change) = grep { $_->node_type ne 'Bug'} @changes;
           is($mergeticket_change->change_type , 'update_file');
        is($mergeticket_change->node_uuid, replica_uuid_for('alice'));
        my @mergeticket_prop_changes = $mergeticket_change->prop_changes;
        is($#mergeticket_prop_changes, 0, "Only updated one merge ticket");
        my $propchange = shift @mergeticket_prop_changes;
        is ($propchange->name, 'last-changeset');
        is($propchange->new_value, as_alice { replica_last_rev() } ); 
       
   }  
    
    
    
#diag `svn log -v $repo`;


    # at the first sign of conflict, we're going to call back to a routine we inject to see if the conflict object is as we expect it
    # Then we'll inject a hard-coded resolution into the conflict object
    # then we'll let the code finish applying it.
    # Then we'll check that bob's current state is right and that bob has a merge-ticket from alice


};


