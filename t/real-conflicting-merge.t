#!/usr/bin/perl 
#
use warnings;
use strict;
use Test::Exception;

use Prophet::Test tests => 12;

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
    run_ok('prophet-node-update', ['--type','Bug','--uuid',$record_id, '--status' => 'open']);
    run_output_matches('prophet-node-show', ['--type', 'Bug', '--uuid', $record_id],
                       ['id: '.$record_id, 'status: open', 'from: alice'],
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

    throws_ok {
        $target->import_changesets(
            from              => $source,
        );
    } qr/not resolved/;

    throws_ok {
        $target->import_changesets(
            from     => $source,
            resolver => sub { die "my way of death\n" },
        );
    } qr/my way of death/, 'our resolver is actually called';

# always ours
use Data::Dumper;
    $target->import_changesets(
            from     => $source,
            resolver => sub { my $conflict = shift;
                            warn Dumper($conflict);
                                return 0 if $conflict->file_op_conflict;

    my $resolution = Prophet::Change->new( { is_resolution => 1, 
                                             change_type => $conflict->change_type,
                                             node_type => $conflict->node_type,
                                             node_uuid => $conflict->node_uuid });


    for my $prop_conflict ( @{$conflict->prop_conflicts} ) {
        $resolution->add_prop_change(
                name => $prop_conflict->name,
                old  => $prop_conflict->source_old_value,
                new  => $prop_conflict->target_value
                );
    }
    return $resolution;

});
my $repo = repo_uri_for('bob');
diag `svn log -v $repo`;

};


