package Prophet::Server::ViewHelpers::ParamFromFunction;

use Template::Declare::Tags;

BEGIN { delete ${__PACKAGE__."::"}{meta}; 
 delete ${__PACKAGE__."::"}{with};
}

use Any::Moose;

use Any::Moose 'Util::TypeConstraints';


=head1 NAME

=head1 METHODS

=head1 DESCRIPTION

=cut


has function => (
    isa => 'Prophet::Server::ViewHelpers::Function',
    is  => 'ro'
);
has name          => ( isa => 'Str',                 is => 'rw' );
has prop          => ( isa => 'Str',                 is => 'ro' );
has from_function => ( isa => 'Prophet::Server::ViewHelpers::Function',                 is => 'rw' );
has from_result   => ( isa => 'Str',                 is => 'rw' );
has field         => ( isa => 'Prophet::Web::Field', is => 'rw' );


sub render {
    my $self = shift;

    my $unique_name = $self->_generate_name();
   
    my $record = $self->function->record;

    my $value = "function-".$self->from_function->name."|result-".$self->from_result;

    $self->field( Prophet::Web::Field->new(
        name   => $unique_name,
        type => 'hidden',
        record => $record,
        value  => $value
        
    ));

    outs_raw( $self->field->render_input );
}




sub _generate_name {
    my $self = shift;
    return "prophet-fill-function-"
        . $self->function->name
        . "-prop-"
        . $self->prop;
}

=head1 METHODS

=cut




__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

