package Prophet::CLI::Command::Mirror;
use Any::Moose;
extends 'Prophet::CLI::Command';

has source => ( isa => 'Prophet::Replica', is => 'rw');
has target => ( isa => 'Prophet::Replica', is => 'rw');

sub ARG_TRANSLATIONS { shift->SUPER::ARG_TRANSLATIONS(),  f => 'force' };

sub run {
    my $self = shift;
    Prophet::CLI->end_pager();

    $self->validate_args();

    $self->set_arg( 'to' => 'prophet_cache:' . $self->app_handle->handle->url . '/remote-replica-cache/' );

    my $source = Prophet::Replica->get_handle(
        url        => $self->arg('from'),
        app_handle => $self->app_handle,
    );
    unless ( $source->replica_exists ) {
        print "The source replica '@{[$source->url]}' doesn't exist or is unreadable.";
        exit 1;
    }

    my $target = Prophet::Replica->get_handle(
        url        => $self->arg('to'),
        app_handle => $self->app_handle,
    );
    $target->uuid( $source->uuid );

    my $target_resdb = Prophet::Replica->get_handle(
        app_handle => $self->app_handle,
        url        => $self->arg('to')
    );
    $target_resdb->uuid($source->resolution_db_handle->uuid);


    if ( !$target->replica_exists && !$target->can_initialize ) {
        die "The target replica path you specified can't be created.\n";
    }

    my %init_args = (
        db_uuid            => $source->db_uuid,
        replica_uuid       => $source->uuid,
    );
    my %resdb_init_args = (
        db_uuid         => $source->resolution_db_handle->db_uuid,
        replica_uuid => $source->resolution_db_handle->uuid,
    );
    $target->initialize(%resdb_init_args);    # XXX only do this when we need to
    $target_resdb->initialize(%init_args);    # XXX only do this when we need to
    $self->mirror_data($source->resolution_db_handle,$target_resdb);
    $self->mirror_data($source,$target);


}
    sub mirror_data {
        my $self = shift;
            my ($source, $target) = @_;

    if ( $source->can('read_changeset_index') ) {
        $target->_write_file(
            path    => $target->changeset_index,
            content => ${ $source->read_changeset_index }
        );

        $target->traverse_changesets(
            load_changesets => 0,
            callback =>

                sub {
                my $data = shift;
                my ( $seq, $orig_uuid, $orig_seq, $key ) = @{$data};
                return
                    if (
                    -f File::Spec->catdir( $target->fs_root,
                        $target->changeset_cas->filename($key) ) );

                my $content = $source->_read_file( $source->changeset_cas->filename($key) );
                utf8::decode($content) if utf8::is_utf8($content);
                my $newkey = $target->changeset_cas->write(
                    $content

                );

                my $existsp = File::Spec->catdir( $target->fs_root,
                    $target->changeset_cas->filename($key) );
                if ( !-f $existsp ) {
                    die "AAA couldn't find changeset $key at $existsp";

                }
                }

            ,
            after => 0,
            until => 10
        );
    } else {
        warn "Sorry, we only support replicas with a changeset index file";
    }
}

sub validate_args {
    my $self = shift;
    die "Please specify a --from.\n"
        unless $self->has_arg('from');
}


__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;
