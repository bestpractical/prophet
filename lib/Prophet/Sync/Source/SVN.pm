use warnings;
use strict;

package Prophet::Sync::Source::SVN;

use SVN::Core;
use SVN::Ra;
use SVK;
use SVK::Config;
use SVN::Delta;
    
use Prophet::Sync::Source::SVN::ReplayEditor;



sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    return $self;
}

sub ra {
    my $self = shift;
    $self->{'_ra'} = shift if (@_);
    return $self->{'_ra'};

}

sub setup{
    my $self = shift;
    my $url = shift;
    my ($baton, $ref) = SVN::Core::auth_open_helper(SVK::Config->get_auth_providers);
    my $config = SVK::Config->svnconfig;
    $self->ra( SVN::Ra->new( url => $url , config => $config, auth => $baton));

} 




sub fetch_changesets {
    my $self = shift;
    my @results;
    my $last_editor;
    my $handle_replayed_txn = sub {
        $last_editor
            = Prophet::Sync::Source::SVN::ReplayEditor->new( _debug => 0 );
        $last_editor->ra($self->ra);
        return $last_editor;
    };

    for my $rev ( 1 .. $self->ra->get_latest_revnum ) {
        $Prophet::Sync::Source::SVN::ReplayEditor::CURRENT_REMOTE_REVNO = $rev;
        # This horrible hack is here because I have no idea how to pass custom variables into the editor
        $self->ra->replay( $rev, 0, 1, $handle_replayed_txn->() );

        push @results, $last_editor->dump_deltas;

    }
    return \@results;
}

1;
