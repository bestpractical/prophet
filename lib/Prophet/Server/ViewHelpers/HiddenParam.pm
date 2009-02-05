package Prophet::Server::ViewHelpers::HiddenParam;

use Template::Declare::Tags;

BEGIN { delete ${__PACKAGE__."::"}{meta}; 
 delete ${__PACKAGE__."::"}{with};
}

use Any::Moose;

extends 'Prophet::Server::ViewHelpers::Widget';


use Any::Moose 'Util::TypeConstraints';


has value => ( isa => 'Str', is => 'rw');


sub render {
    my $self = shift;

    my $unique_name = $self->_generate_name();
   
    my $record = $self->function->record;

    $self->field( Prophet::Web::Field->new(
        name   => $unique_name,
        id      => $unique_name,
        record => $record,
        class  => 'hidden-prop-'.$self->prop.' function-'.$self->function->name,
        value  => $self->value,
        type => 'hidden')
        
    );

    outs_raw( $self->field->render_input );

}
__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

