package Prophet::CLI::Dispatcher;
use Path::Dispatcher::Declarative -base;
use Moose;

use Prophet::CLI;

has cli => (
    is       => 'rw',
    isa      => 'Prophet::CLI',
    required => 1,
);

has context => (
    is       => 'rw',
    isa      => 'Prophet::CLIContext',
    lazy     => 1,
    default  => sub {
        my $self = shift;
        $self->cli->context;
    },
);

has dispatching_on => (
    is       => 'rw',
    isa      => 'ArrayRef',
    required => 1,
);

has record => (
    is            => 'rw',
    isa           => 'Prophet::Record',
    documentation => 'If the command operates on a record, it will be stored here.',
);

on server => sub {
    my $self = shift;
    my $server = $self->setup_server;
    $server->run;
};

on create => sub {
    my $self   = shift;
    my $record = $self->context->_get_record_object;

    my ($val, $msg) = $record->create(props => $self->cli->edit_props);

    if (!$val) {
        warn "Unable to create record: " . $msg . "\n";
    }
    if (!$record->uuid) {
        warn "Failed to create " . $record->record_type . "\n";
        return;
    }

    $self->record($record);

    printf "Created %s %s (%s)\n",
        $record->record_type,
        $record->luid,
        $record->uuid;
};

on delete => sub {
    my $self = shift;

    $self->context->require_uuid;
    my $record = $self->context->_load_record;
    my $deleted = $record->delete;

    if ($deleted) {
        print $record->type . " " . $record->uuid . " deleted.\n";
    } else {
        print $record->type . " " . $record->uuid . " could not be deleted.\n";
    }

};

on update => sub {
    my $self = shift;

    $self->context->require_uuid;
    my $record = $self->context->_load_record;

    my $new_props = $self->cli->edit_record($record);
    my $updated = $record->set_props( props => $new_props );

    if ($updated) {
        print $record->type . " " . $record->luid . " (".$record->uuid.")"." updated.\n";

    } else {
        print "SOMETHING BAD HAPPENED "
            . $record->type . " "
            . $record->luid . " ("
            . $record->uuid
            . ") not updated.\n";
    }
};

on qr/()/ => sub {
    my $self = shift;
    $self->fatal_error("The command you ran could not be found. Perhaps running '$0 help' would help?");
};

sub fatal_error {
    my $self   = shift;
    my $reason = shift;

    # always skip this fatal_error function when generating a stack trace
    local $Carp::CarpLevel = $Carp::CarpLevel + 1;

    die $reason . "\n";
}

sub setup_server {
    my $self = shift;
    require Prophet::Server;
    my $server = Prophet::Server->new($self->context->arg('port') || 8080);
    $server->app_handle($self->context->app_handle);
    $server->setup_template_roots;
    return $server;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

