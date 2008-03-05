use warnings;
use strict;

package Prophet::Sync::Source::SVN;
use base qw/Class::Accessor/;
use Params::Validate;

use SVN::Core;
use SVN::Ra;
use SVK;
use SVK::Config;
use SVN::Delta;

use Prophet::Handle;
use Prophet::Sync::Source::SVN::ReplayEditor;
use Prophet::ChangeSet;

__PACKAGE__->mk_accessors(qw/url ra prophet_handle/);

sub new {
    my $self = shift->SUPER::new(@_);
    $self->setup();
    return $self;
}

sub setup {
    my $self = shift;
    my ( $baton, $ref )
        = SVN::Core::auth_open_helper( SVK::Config->get_auth_providers );
    my $config = SVK::Config->svnconfig;
    $self->ra(
        SVN::Ra->new( url => $self->url, config => $config, auth => $baton )
    );

    if ( $self->url =~ /^file:\/\/(.*)$/ ) {
        warn "Connecting to $1";
        $self->prophet_handle(
            Prophet::Handle->new(
                { repository => $1, db_root => '_prophet' }
            )
        );
    }

}

sub unique_id {
    my $self = shift;
    return $self->ra->get_uuid;
}

sub fetch_changesets {
    my $self = shift;
    my @results;
    my $last_editor;
    my $handle_replayed_txn = sub {
        $last_editor
            = Prophet::Sync::Source::SVN::ReplayEditor->new( _debug => 0 );
        $last_editor->ra( $self->ra );
        return $last_editor;
    };

    for my $rev ( 1 .. $self->ra->get_latest_revnum ) {
        $Prophet::Sync::Source::SVN::ReplayEditor::CURRENT_REMOTE_REVNO
            = $rev;

# This horrible hack is here because I have no idea how to pass custom variables into the editor
        $self->ra->replay( $rev, 0, 1, $handle_replayed_txn->() );

        push @results, $last_editor->dump_deltas;

    }

    # XXX TODO, we should be creating the changesets directly earlier
    my @changesets;
    for my $entry (@results) {
        my $changeset = Prophet::ChangeSet->new(
            {   change_uuid => $entry->{'revision'},
                source_uuid => $self->unique_id
            }
        );
        for my $path ( keys %{ $entry->{'paths'} } ) {
            if ( $path =~ qr|^(.+)/(.*?)/(.*?)$| ) {
                my ( $prefix, $type, $record ) = ( $1, $2, $3 );
                my $change = Prophet::Change->new(
                    {   node_type   => $type,
                        node_uuid   => $record,
                        change_type => $entry->{'paths'}->{$path}->{'fs'}
                    }
                );
                for my $name (
                    keys %{ $entry->{'paths'}->{$path}->{prop_deltas} } )
                {
                    warn "Changing $name for $change";
                    $change->add_prop_change(
                        name => $name,
                        old =>
                            $entry->{paths}->{$path}->{prop_deltas}->{$name}
                            ->{'old'},
                        new =>
                            $entry->{paths}->{$path}->{prop_deltas}->{$name}
                            ->{'new'},
                    );
                }

                $changeset->add_change( change => $change );
            } else {
                warn "Discarding change to a non-record: $path";
                warn "Someday, we should be less stupid about this";
            }

        }
        warn YAML::Dump($changeset);

    }

    exit;
    return \@changesets;
}

sub accepts_changesets {
    my $self = shift;
    return 1 if $self->prophet_handle;
    return undef;
}

# XXX TODO this is hacky as hell and violates abstraction barriers in the name of doing things over the RA
sub last_changeset_for_source {
    my $self = shift;
    my %args = validate( @_, { source => 1 } );
    my ( $stream, $pool );

    # XXX HACK
    my $filename = join( "/",
        "_prophet", $Prophet::Handle::MERGETICKET_METATYPE,
        $args{'source'} );
    my ( $rev_fetched, $props ) = eval {
        $self->ra->get_file( $filename, $self->ra->get_latest_revnum,
            $stream, $pool );
    };
    return ( $props->{'last-rev'} );

}

sub record_changeset_for_source {
    my $self = shift;
    return undef unless ( $self->accepts_changesets );
    my %args = validate( @_, { source => 1, changeset => 1 } );
    $self->prophet_handle->record_changeset_for_source(%args);

}

1;
