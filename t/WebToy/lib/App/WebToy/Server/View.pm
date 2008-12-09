package App::WebToy::Server::View;
use base 'Prophet::Server::View';
use Template::Declare::Tags;
use Prophet::Server::ViewHelpers;
use App::WebToy::Collection::WikiPage;

=head1 NAME

=head1 METHODS

=head1 DESCRIPTION

=cut

=head1 METHODS

=cut

template 'abc' => page {
    my $self = shift;
    my $c = App::WebToy::Collection::WikiPage->new(app_handle => $self->app_handle);
    $c->matching(sub { return 1});
    my $r = $c->items->[0];
    h1 { $r->prop('title')};
    
    form {
        my $f = function( record => $r, action => 'update');
        my $w = widget( function => $f, prop => 'title');
        widget( function => $f, prop => 'content');
        input {attr { label => 'save', type => 'submit'}};
    };



    form {
        my $f = function( record => App::WebToy::Model::WikiPage->new(app_handle => $self->app_handle ), 
                          action => 'create');
        widget( function => $f, prop => 'title');
        widget( function => $f, prop => 'content');
        input {attr { label => 'save', type => 'submit'}};

}



};


1;

