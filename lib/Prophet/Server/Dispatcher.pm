package Prophet::Server::Dispatcher;
use Moose;
use Path::Dispatcher::Declarative -base;

has server => ( isa => 'Prophet::Server', is => 'rw', weak_ref => 1 );

sub token_delimiter       {'/'}
sub case_sensitive_tokens {0}

under 'POST' => sub {
    on qr'.*' => sub {
        my $self = shift;
        return $self->server->_send_401 if ( $self->server->read_only );
        next_rule;
    };

    under 'records' => sub {
        on qr|^(.*)/(.*)/(.*)$| => sub { shift->server->update_record_prop($1,$2,$3) };
        on qr|^(.*)/(.*).json$| => sub { shift->server->update_record($1,$2) };
        on qr|^(.*).json$|     => sub { shift->server->create_record($1) };
    };
};

under 'GET' => sub {
    on qr'^=/prophet/autocomplete' => sub {
        shift->server->show_template('/_prophet_autocompleter') };
    on qr'^static/prophet/(.*)$' => sub { shift->server->send_static_file($1)};
    on qr'replica/+(.*)$' => sub { shift->server->serve_replica($1) };
    on 'records.json' => sub { shift->server->get_record_types };
    under 'records' => sub {
        on qr|^(.*)/(.*)/(.*)$| => sub { shift->server->get_record_prop($1,$2,$3); };
        on qr|^(.*)/(.*).json$| => sub { shift->server->get_record($1,$2) };
        on qr|^(.*).json$|      => sub { shift->server->get_record_list($1) };
    };
};

on qr'^(?:GET|POST|PUT|DELETE|PATCH)/(.*)$' => sub { shift->server->show_template($1) || next_rule; };

no Moose;

1;
