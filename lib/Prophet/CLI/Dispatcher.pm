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

on show => sub {
    my $self = shift;

    $self->context->require_uuid;
    my $record = $self->context->_load_record;

    print $self->cli->stringify_props(
        record  => $record,
        batch   => $self->context->has_arg('batch'),
        verbose => $self->context->has_arg('verbose'),
    );
};

on config => sub {
    my $self = shift;

    my $config = $self->cli->config;

    print "Configuration:\n\n";
    my @files = @{$config->config_files};
    if (!scalar @files) {
        print $self->no_config_files;
        return;
    }

    print "Config files:\n\n";
    for my $file (@files) {
        print "$file\n";
    }

    print "\nYour configuration:\n\n";
    for my $item ($config->list) {
        print $item ." = ".$config->get($item)."\n";
    }
};

on export => sub {
    my $self = shift;
    $self->cli->handle->export_to( path => $self->context->arg('path') );
};

on history => sub {
    my $self = shift;

    $self->context->require_uuid;
    my $record = $self->context->_load_record;
    $self->record($record);
    print $record->history_as_string;
};

on log => sub {
    my $self   = shift;
    my $handle = $self->cli->handle;
    my $newest = $self->context->arg('last') || $handle->latest_sequence_no;
    my $start  = $newest - ( $self->context->arg('count') || '20' );
    $start = 0 if $start < 0;

    $handle->traverse_changesets(
        after    => $start,
        callback => sub {
            my $changeset = shift;
            $self->changeset_log($changeset);
        },
    );

};

on merge => sub {
    my $self = shift;

    my (@alt_from, @alt_to);

    if ($self->context->has_arg('db_uuid')) {
        push @alt_from, join '/',
                            $self->context->arg('from'),
                            $self->context->arg('db_uuid');
        push @alt_to, join '/',
                          $self->context->arg('to'),
                          $self->context->arg('db_uuid');
    }

    my $source = Prophet::Replica->new(
        url        => $self->context->arg('from'),
        app_handle => $self->context->app_handle,
        _alt_urls  => \@alt_from,
    );

    my $target = Prophet::Replica->new(
        url        => $self->context->arg('to'),
        app_handle => $self->context->app_handle,
        _alt_urls  => \@alt_to,
    );

    $target->import_resolutions_from_remote_replica(
        from  => $source,
        force => $self->context->has_arg('force'),
    );

    my $changesets = $self->_do_merge( $source, $target );

    $self->print_merge_report($changesets);
};


# catch-all. () makes sure we don't hit the annoying historical feature of
# the empty regex meaning the last-used regex
on qr/()/ => sub {
    my $self = shift;
    $self->fatal_error("The command you ran '$_' could not be found. Perhaps running '$0 help' would help?");
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

sub no_config_files {
    my $self = shift;
    return "No configuration files found. "
         . " Either create a file called 'prophetrc' inside of "
         . $self->cli->handle->fs_root
         . " or set the PROPHET_APP_CONFIG environment variable.\n\n";
}

sub changeset_log {
    my $self      = shift;
    my $changeset = shift;
    print $changeset->as_string(
        change_header => sub {
            my $change = shift;
            $self->change_header($change);
        }
    );
}

sub change_header {
    my $self   = shift;
    my $change = shift;
    return
          " # "
        . $change->record_type . " "
        . $self->cli->handle->find_or_create_luid(
        uuid => $change->record_uuid )
        . " ("
        . $change->record_uuid . ")\n";
}

sub print_merge_report {
    my $self = shift;
    my $changesets = shift;
    if ($changesets == 0) {
        print "No new changesets.\n";
    }
    elsif ($changesets == 1) {
        print "Merged one changeset.\n";
    }
    else {
        print "Merged $changesets changesets.\n";
    }
}

=head2 _do_merge $source $target

Merges changesets from the source replica into the target replica.

Fails fatally if the source and target are the same, or the target is
not writable.

Conflicts are resolved by either the resolver specified in the
C<PROPHET_RESOLVER> environmental variable, the C<prefer> argument
(can be set to C<to> or C<from>, in which case Prophet will
always prefer changesets from one replica or the other), or by
using a default resolver.

Returns the number of changesets merged.

=cut

sub _do_merge {
    my ( $self, $source, $target ) = @_;

    my %import_args = (
        from  => $source,
        resdb => $self->cli->resdb_handle,
        force => $self->context->has_arg('force'),
    );

    local $| = 1;

    $self->validate_merge_replicas($source => $target);

    $import_args{resolver_class} = $self->merge_resolver();

    my $changesets = 0;

    my $source_latest = $source->latest_sequence_no() || 0;
    my $source_last_seen = $target->last_changeset_from_source($source->uuid) || 0;

    if( $self->context->has_arg('verbose') ) {
        print "Integrating changes from ".$source_last_seen . " to ". $source_latest."\n";
    }


    if( $self->context->has_arg('verbose') ) {
        $import_args{reporting_callback} = sub {
            my %args = @_;
            print $args{changeset}->as_string;
            $changesets++;
        };
    } else {
        require Time::Progress;
        my $progress = Time::Progress->new();
        $progress->attr( max => ($source_latest - $source_last_seen));

        $import_args{reporting_callback} = sub {
            my %args = @_;
            $changesets++;
            print $progress->report( "%30b %p %E // ". ($args{changeset}->created || 'Undated'). " " .(sprintf("%-12s",$args{changeset}->creator||'')) ."\r" , $changesets);

        };
    }

    $target->import_changesets(%import_args);
    return $changesets;
}


sub validate_merge_replicas {
    my $self = shift;
    my $source = shift;
    my $target = shift;

    if ( $target->uuid eq $source->uuid ) {
        $self->fatal_error(
                  "You appear to be trying to merge two identical replicas. "
                . "Either you're trying to merge a replica to itself or "
                . "someone did a bad job cloning your database." );
    }

    if ( !$target->can_write_changesets ) {
        $self->fatal_error(
            $target->url
            . " does not accept changesets. Perhaps it's unwritable."
        );
    }
}

sub merge_resolver {
    my $self = shift;

    my $prefer = $self->context->arg('prefer') || 'none';

    my $resolver = $ENV{'PROPHET_RESOLVER'} ? 'Prophet::Resolver::' . $ENV{'PROPHET_RESOLVER'}
        : $prefer eq 'to'   ? 'Prophet::Resolver::AlwaysTarget'
        : $prefer eq 'from' ? 'Prophet::Resolver::AlwaysSource'
        :                     ();
    return $resolver;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

