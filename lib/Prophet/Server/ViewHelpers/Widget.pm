package Prophet::Server::ViewHelpers::Widget;

use Template::Declare::Tags;

BEGIN { delete ${__PACKAGE__."::"}{meta}; 
 delete ${__PACKAGE__."::"}{with};
}

use Moose;

use Moose::Util::TypeConstraints;


=head1 NAME

=head1 METHODS

=head1 DESCRIPTION

=cut


has function => (
    isa => 'Prophet::Server::ViewHelpers::Function',
    is  => 'ro'
);
has name => ( isa => 'Str', is => 'rw' );
has prop => ( isa => 'Str', is => 'ro' );




sub render {
    my $self = shift;

    my $f = Prophet::Web::Field->new(
        name       => $self->_generate_name(),
            record => $self->function->record,
        label => $self->prop,
        value => $self->function->record->prop( $self->prop )
    );
    outs_raw( $f->render );
}




sub _generate_name {
    my $self = shift;
    return
          "prophet-field||function-"
        . $self->function->name
        . "|prop-"
        . $self->prop . "|";
}

=head1 METHODS

=cut




__PACKAGE__->meta->make_immutable;
no Moose;

1;

