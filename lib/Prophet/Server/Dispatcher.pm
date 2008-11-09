package Prophet::Server::Dispatcher;
use Moose;
use Path::Dispatcher::Declarative -base;

has server => ( isa => 'Prophet::Server', is => 'rw', weak_ref =>1);


sub token_delimiter { '/' }
sub case_sensitive_tokens { 0 }

under 'GET' => sub {

    on 'replica' => sub {
        my $server = shift;
        return $server->handle_request_get_replica();
    };
    on 'records.json' => sub {
        my $server = shift;
        return $server->send_content( encode_as => 'json',
                                    content      =>  $server->handle->list_types );
    };




    under 'records' => sub {

        on qr|(.*)/(.*)/(.*)| => sub {
            my $server = shift;
            my $type   = $1;
            my $uuid   = $2;
            my $prop   = $3;
            my $record = $server->load_record( type => $type, uuid => $uuid );
            return $server->_send_404 unless ($record);
            if ( my $val = $record->prop($prop) ) {
                return $server->send_content(
                    content_type => 'text/plain',
                    content      => $val
                );
            } else {
                return $server->_send_404();
            }
        };
        on qr|(.*)/(.*).json| => sub {
            my $server = shift;
            my $type   = $1;
            my $uuid   = $2;
            my $record = $server->load_record( type => $type, uuid => $uuid );
            return $server->_send_404 unless ($record);
            return $server->send_content(
                encode_as =>'json',
                content      =>  $record->get_props 
            );
        };

        on qr|(.*).json| => sub {
            my $server = shift;
            my $type = $1;
            require Prophet::Collection;
            my $col = Prophet::Collection->new(
                handle => $server->handle,
                type   => $type
            );
            $col->matching( sub {1} );
            warn "Query language not implemented yet.";
            return $server->send_content(
                encode_as => 'json',
                content      => 
                    {   map {
                            $_->uuid => "/records/$type/" . $_->uuid . ".json"
                            } @$col
                    }
                
            );
        };

        on '*' => sub {
            my $server = shift;
            return $server->handle_request_get_template();
        };
    };

};

on '*' =>  sub {return undef};

no Moose;

1;
