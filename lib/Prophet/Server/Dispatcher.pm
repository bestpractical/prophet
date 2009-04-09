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
    on qr'^/replica/+(.*)$' => sub { shift->server->serve_replica($1) };
    on qr'^/records.json' => sub { shift->server->get_record_types };
    under qr'/records' => sub {
        on qr|^/(.*)/(.*)/(.*)$| => sub { shift->server->get_record_prop($1,$2,$3); };
        on qr|^/(.*)/(.*).json$| => sub { shift->server->get_record($1,$2) };
        on qr|^/(.*).json$|      => sub { shift->server->get_record_list($1) };
    };
};

on qr'^(.*)$' => sub { shift->server->show_template($1) || next_rule; };

no Any::Moose;

1;
