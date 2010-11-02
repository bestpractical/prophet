package Prophet::Server::ViewHelpers::Widget;

use Template::Declare::Tags;

BEGIN { delete ${__PACKAGE__."::"}{meta}; 
 delete ${__PACKAGE__."::"}{with};
}

use Any::Moose;

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

has field => ( isa => 'Prophet::Web::Field', is => 'rw');

has type => ( isa => 'Str|Undef', is => 'rw');

has autocomplete => (isa => 'Bool', is => 'rw', default => 1);

has default => ( isa => 'Str|Undef', is => 'rw');

sub render {
    my $self = shift;

    my $unique_name = $self->_generate_name();
   
    my $record = $self->function->record;

    my $value;

    if (defined $self->default) {
        $value = $self->default;
    } elsif ( $self->function->action eq 'create' ) {
        if ( my $method = $self->function->record->can( 'default_prop_' . $self->prop ) ) {
            $value = $method->( $self->function->record );
        } else {
            $value = '';
        }
    } elsif ( $self->function->action eq 'update' && $self->function->record->loaded ) {
        $value = $self->function->record->prop( $self->prop ) || '';
    } else {
        $value = '';
    }

    $self->field( Prophet::Web::Field->new(
        name   => $unique_name,
        id      => $unique_name,
        record => $record,
        label  => $self->prop,
        class  => 'prop-'.$self->prop.' function-'.$self->function->name,
        value  => $value,
        ($self->type ? ( type => $self->type) : ())
        
    ));

    my $orig = Prophet::Web::Field->new(
        name  => "original-value-". $unique_name,
        value => $value,
        type  => 'hidden'
    );

    outs_raw( $self->field->render );
    outs_raw( $orig->render_input );
    if ($self->autocomplete) {
        $self->_render_autocompleter();
    }

}

sub _render_autocompleter {
    my $self = shift;
    my $record = $self->function->record();
        outs_raw('<script>$("#'.$self->field->id.'").autocomplete("/=/prophet/autocomplete",{ 
        selectFirst: true, autoFill: false, minChars: 0, delay: 0,
        extraParams: {
                    "function": "'.$self->field->name.'",
                    "class": "'.ref($record).'",
                    "uuid": "'.($record->uuid||'').'",
                    "type": "'.$record->type.'",
                    "prop": "'.$self->prop.'" } }   ); </script> ');
}

sub _generate_name {
    my $self = shift;
    return
          "prophet-field-function-"
        . $self->function->name
        . "-prop-"
        . $self->prop;
}

=head1 METHODS

=cut

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

