package Prophet::Server::Dispatcher;
use Moose;
use Path::Dispatcher::Declarative -base;

has server => ( isa => 'Prophet::Server', is => 'rw', weak_ref => 1 );

sub token_delimiter       {'/'}
sub case_sensitive_tokens {0}

my $SERVER;

on qr'.*' => sub { $SERVER = shift; next_rule; };

under 'POST' => sub {
    on qr'.*' => sub {
        return $SERVER->_send_401 if ( $SERVER->read_only );
        next_rule;
    };

    under 'records' => sub {
        on qr|(.*)/(.*)/(.*)| => sub { $SERVER->update_record_prop() };
        on qr|(.*)/(.*).json| => sub { $SERVER->update_record() };
        on qr|^(.*).json|     => sub { $SERVER->create_record() };
    };
};

under 'GET' => sub {
    on qr'replica/+(.*)$' => sub { $SERVER->serve_replica() };
    on 'records.json' => sub { $SERVER->get_record_types };
    under 'records' => sub {
        on qr|(.*)/(.*)/(.*)| => sub { $SERVER->get_record_prop() };
        on qr|(.*)/(.*).json| => sub { $SERVER->get_record() };
        on qr|(.*).json|      => sub { $SERVER->get_record_list() };
        on '^(.*)$'           => sub { $SERVER->show_template() };
    };
};

on '*' => sub { return undef };

no Moose;

1;
