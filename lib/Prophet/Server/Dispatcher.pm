package Prophet::Server::Dispatcher;
use Any::Moose;
use Path::Dispatcher::Declarative -base, -default => {
    token_delimiter => '/',
};

has server => ( isa => 'Prophet::Server', is => 'rw', weak_ref => 1 );

under { method => 'POST' } => sub {
    on qr'.*' => sub {
        my $self = shift;
        return $self->server->_send_401 if ( $self->server->read_only );
        next_rule;
    };

    under qr'/records' => sub {
        on qr|^/(.*)/(.*)/(.*)$| => sub { shift->server->update_record_prop($1,$2,$3) };
        on qr|^/(.*)/(.*).json$| => sub { shift->server->update_record($1,$2) };
        on qr|^/(.*).json$|     => sub { shift->server->create_record($1) };
    };
};

under { method => 'GET' } => sub {
    on qr'^/=/prophet/autocomplete' => sub {
        shift->server->show_template('/_prophet_autocompleter') };
    on qr'^/static/prophet/(.*)$' => sub { shift->server->send_static_file($1)};

   on qr'^/records.json' => sub { shift->server->get_record_types };
    under qr'/records' => sub {
        on qr|^/(.*)/(.*)/(.*)$| => sub { shift->server->get_record_prop($1,$2,$3); };
        on qr|^/(.*)/(.*).json$| => sub { shift->server->get_record($1,$2) };
        on qr|^/(.*).json$|      => sub { shift->server->get_record_list($1) };

    };

    on qr'^/replica(/resolutions)?' => sub {
        my $self = shift;
        if ($1 && $1 eq '/resolutions') {
            $_->metadata->{replica_handle} = $self->server->app_handle->handle->resolution_db_handle;
        } else {
            $_->metadata->{replica_handle} = $self->server->app_handle->handle;
        }
        next_rule;
    };

    under qr'^/replica(/resolutions/)?' => sub {
        on 'replica-version' => sub { shift->server->send_replica_content('1')};
        on 'replica-uuid' => sub { my $self = shift; $self->server->send_replica_content( $_->metadata->{replica_handle}->uuid ); };
        on 'database-uuid' => sub { my $self = shift; $self->server->send_replica_content( $_->metadata->{replica_handle}->db_uuid ); };
        on 'latest-sequence-no' => sub { my $self = shift; $self->server->send_replica_content( $_->metadata->{replica_handle}->latest_sequence_no ); };
        
        on 'changesets.idx' => sub {
            my $self  = shift;
            my $index = '';
            my $repl = $_->metadata->{replica_handle};
            $repl->traverse_changesets(
                after=> 0,
                load_changesets => 0,
                callback => sub {
                    my %args = (@_);
                    my $data            = $args{changeset_metadata};
                    my $changeset_index_line = pack( 'Na16NH40',
                        $data->[0],
                        $repl->uuid_generator->from_string( $data->[1]),
                        $data->[2],
                        $data->[3]);
                    $index .= $changeset_index_line;
                }
            );
            $self->server->send_replica_content($index);
        };
        on qr|cas/changesets/././(.{40})$| => sub {
            my $self = shift;
            my $sha1 = $1;
            $self->server->send_replica_content($_->metadata->{replica_handle}->fetch_serialized_changeset(sha1 => $sha1));
        } ;


    };
};

on qr'^(.*)$' => sub { shift->server->show_template($1) || next_rule; };

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;
