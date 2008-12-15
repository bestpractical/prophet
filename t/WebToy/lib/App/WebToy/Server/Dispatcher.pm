package App::WebToy::Server::Dispatcher;
use Prophet::Server::Dispatcher -base;

redispatch_to 'Prophet::Server::Dispatcher';


sub show_template {
    if(ref($_[0])) {
        # called in oo context. do it now
        my $self = shift;
        my $template = shift;
        $self->server->show_template($template, @_);
    } else {

    my $template = shift;
    return sub {
        my $self = shift;
        $self->server->show_template($template, @_);
    };
    }
}

1;
