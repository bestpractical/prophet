package Prophet::ReplicaExporter;
use Moose;
use Params::Validate qw(:all);
use Path::Class;
use Prophet::Record;
use Prophet::Collection;

has source_replica => (
    is  => 'rw',
    isa => 'Prophet::Replica',
);

has target_path => (
    is        => 'rw',
    isa       => 'Path::Class::Dir',
    predicate => 'has_target_path',
);

has target_replica => (
    is      => 'rw',
    isa     => 'Prophet::Replica',
    lazy    => 1,
    default => sub {
        my $self = shift;
        confess "No target_path specified" unless $self->has_target_path;
        my $replica = Prophet::Replica->new(url => "prophet:file://" . $self->target_path, app_handle => $self->app_handle);
        $replica->initialize(db_uuid => $self->source_replica->db_uuid);
        return $replica;
    },
);

has app_handle => (
    is        => 'ro',
    isa       => 'Prophet::App',
    weak_ref  => 1,
    predicate => 'has_app_handle',
);

=head1 NAME

Prophet::ReplicaExporter

=head1 DESCRIPTION
                        
A utility class which exports a replica to a serialized on-disk format


=cut

=head1 METHODS

=head2 new

Instantiates a new replica exporter object

=cut

=head2 export

This routine will export a copy of this prophet database replica to a flat file on disk suitable for 
publishing via HTTP or over a local filesystem for other Prophet replicas to clone or incorporate changes from.


=cut

sub export {
    my $self = shift;

    $self->_init_export_metadata();
    $self->export_records( type => $_ )
        for ( @{ $self->source_replica->list_types } );
    $self->export_changesets();

    unless ($self->source_replica->is_resdb) {
    my $resolutions = Prophet::ReplicaExporter->new(
           target_path => dir($self->target_path, 'resolutions' ),
            source_replica => $self->source_replica->resolution_db_handle,
            app_handle => $self->app_handle
        
    );
    $resolutions->export();
    }
}

sub _init_export_metadata {
    my $self = shift;
    $self->target_replica->set_latest_sequence_no(
        $self->source_replica->latest_sequence_no );
    $self->target_replica->set_replica_uuid( $self->source_replica->uuid );

}

sub export_records {
    my $self = shift;
    my %args = validate( @_, { type => 1 } );

    my $collection = Prophet::Collection->new(
        app_handle => $self->app_handle,
        handle => $self->source_replica,
        type   => $args{type}
    );
    $collection->matching( sub {1} );
    $self->target_replica->_write_record( record => $_ ) for @$collection;

}

sub export_changesets {
    my $self = shift;

    my $cs_file = $self->target_replica->_get_changeset_index_handle();
    for my $changeset (
        @{ $self->source_replica->fetch_changesets( after => 0 ) } )
    {
        $self->target_replica->_write_changeset(
            index_handle => $cs_file,
            changeset    => $changeset
        );

    }
    close($cs_file);
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
