package Prophet::CLI::RecordCommand;
use Moose::Role;

has type => (
    is       => 'rw',
    isa      => 'Str',
    required => 0,
);

has uuid => (
    is       => 'rw',
    isa      => 'Str',
    required => 0,
);

has record_class => (
    is  => 'rw',
    isa => 'Prophet::Record',
);


sub _get_record_class {
    my $self = shift;
     my $args = { handle => $self->cli->app_handle->handle, type => $self->type };
    if (my $class =  $self->record_class ) {
        Prophet::App->require_module($class);
        return $class->new( $args);
    } elsif ( $self->type ) {
        return $self->_type_to_record_class( $self->type )->new($args);
    } else { Carp::confess("I was asked to get a record object, but I have neither a type nor a record class")}

}

sub _load_record {
    my $self = shift;
    my $record = $self->_get_record_class;
        $record->load( uuid => $self->uuid )
        || $self->fatal_error("I couldn't find the record " . $self->uuid);
    return $record;
}

sub _type_to_record_class {
    my $self = shift;
    my $type = shift;
    my $try = $self->cli->app_class . "::Model::" . ucfirst( lc($type) );
    Prophet::App->require_module($try);    # don't care about fails
    return $try if ( $try->isa('Prophet::Record') );

    $try = $self->cli->app_class . "::Record";
    Prophet::App->require_module($try);    # don't care about fails
    return $try if ( $try->isa('Prophet::Record') );
    return 'Prophet::Record';
}

no Moose::Role;

1;

