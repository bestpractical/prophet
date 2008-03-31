#!/usr/bin/perl 
#
use warnings;
use strict;

use Prophet::Test tests => 9;

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
    run_ok('prophet-node-update', ['--type','Bug','--uuid',$record_id, '--status' => 'closed']);
   my ($ret,$out,$err)=  run_script('prophet-node-show', ['--type','Bug','--uuid',$record_id]);
    diag($out);

};

as_bob {
    # XXX TODO: this should actually fail right now.
    run_ok('prophet-merge', ['--to', repo_uri_for('bob'), '--from', repo_uri_for('alice')], "Sync ran ok!");

};


