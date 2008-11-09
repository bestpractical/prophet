package Prophet::Server::Dispatcher;
use Moose;
use Path::Dispatcher::Declarative -base;

has server => ( isa => 'Prophet::Server', is => 'rw', weak_ref =>1);


sub token_delimiter { '/' }
sub case_sensitive_tokens { 0 }

my $SERVER;

on qr'.*' => sub { $SERVER = shift; next_rule;};

on 'POST' => sub {
    return $SERVER->_send_401 if ( $SERVER->read_only );
    next_rule;
};

under 'POST' => sub {

    under 'records' => sub {
        on qr|(.*)/(.*)/(.*)| => sub {
            my $type = $1;
            my $uuid = $2;
            my $prop = $3;

            my $record = $SERVER->load_record( type => $type, uuid => $uuid );
            return $SERVER->_send_404 unless ($record);
            $record->set_props(
                props => { $prop => ( $SERVER->cgi->param('value') || undef ) }
            );
            return $SERVER->_send_redirect(
                to => "/records/$type/$uuid/$prop" );
        };
        on qr|(.*)/(.*).json| => sub {
            my $type   = $1;
            my $uuid   = $2;
            my $record = $SERVER->load_record( type => $type, uuid => $uuid );

            return $SERVER->_send_404 unless ($record);

            my $ret = $record->set_props(
                props => {
                    map { $_ => $SERVER->cgi->param($_) } $SERVER->cgi->param()
                }
            );
            $SERVER->_send_redirect( to => "/records/$type/$uuid.json" );
        };
        on qr|^(.*).json| => sub {
            my $type   = $1;
            my $record = $SERVER->load_record( type => $type );
            my $uuid   = $record->create(
                props => {
                    map { $_ => $SERVER->cgi->param($_) } $SERVER->cgi->param()
                }
            );
            return $SERVER->_send_redirect( to => "/records/$type/$uuid.json" );
        };
    };
};


under 'GET' => sub {
    on qr'replica/+(.*)$' => sub {
        my $repo_file = $1;
        return undef unless $SERVER->handle->can('read_file');
       my $content = $SERVER->handle->read_file($repo_file);
       return unless defined $content && length($content);
       return $SERVER->send_content( content_type => 'application/x-prophet', content      => $content);
    };

    on 'records.json' => sub {
        warn "SERVER IS ".server();
        return $SERVER->send_content( encode_as => 'json',
                                    content      =>  $SERVER->handle->list_types );
    };




    under 'records' => sub {

        on qr|(.*)/(.*)/(.*)| => sub {
            my $type   = $1;
            my $uuid   = $2;
            my $prop   = $3;
            my $record = $SERVER->load_record( type => $type, uuid => $uuid );
            return $SERVER->_send_404 unless ($record);
            if ( my $val = $record->prop($prop) ) {
                return $SERVER->send_content(
                    content_type => 'text/plain',
                    content      => $val
                );
            } else {
                return $SERVER->_send_404();
            }
        };
        on qr|(.*)/(.*).json| => sub {
            my $type   = $1;
            my $uuid   = $2;
            my $record = $SERVER->load_record( type => $type, uuid => $uuid );
            return $SERVER->_send_404 unless ($record);
            return $SERVER->send_content(
                encode_as =>'json',
                content      =>  $record->get_props 
            );
        };

        on qr|(.*).json| => sub {
            my $type = $1;
            require Prophet::Collection;
            my $col = Prophet::Collection->new(
                handle => $SERVER->handle,
                type   => $type
            );
            $col->matching( sub {1} );
            warn "Query language not implemented yet.";
            return $SERVER->send_content(
                encode_as => 'json',
                content      => 
                    {   map {
                            $_->uuid => "/records/$type/" . $_->uuid . ".json"
                            } @$col
                    }
                
            );
        };

        on '^(.*)$' => sub {
            my $p = $1;
            if (Template::Declare->has_template($p)) {
                Prophet::Server::View->app_handle($SERVER->app_handle);
                my $content = Template::Declare->show($p);
                return $SERVER->send_content( content_type => 'text/html', content      => $content,);
            }
        };
    };

};

on '*' =>  sub {return undef};

no Moose;

1;
