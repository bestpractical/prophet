package Prophet::Web::Field;
use Any::Moose;

has name   => ( isa => 'Str',             is => 'rw' );
has record => ( isa => 'Prophet::Record', is => 'rw' );
has prop  => ( isa => 'Str',             is => 'rw' );
has value  => ( isa => 'Str',             is => 'rw' );
has label => ( isa => 'Str', is => 'rw', default => sub {''});
has id    => ( isa => 'Str|Undef', is => 'rw' );
has class => ( isa => 'Str|Undef', is => 'rw' );
has value => ( isa => 'Str|Undef', is => 'rw' );
has type => ( isa => 'Str|Undef', is => 'rw', default => 'text');



sub _render_attr {
    my $self = shift;
    my $attr = shift;
    my $value = $self->$attr() || return '';
    Prophet::Util::escape_utf8(\$value);
    return $attr . '="' . $value . '"';
}

sub render_name {
    my $self = shift;
    $self->_render_attr('name');

}

sub render_id {
    my $self = shift;
    $self->_render_attr('id');
}

sub render_class {
    my $self = shift;
    $self->_render_attr('class');
}

sub render_value {
    my $self = shift;
    $self->_render_attr('value');
}

sub render {
    my $self = shift;

    my $output = <<EOF;
<label @{[$self->render_name]} @{[$self->render_class]}>@{[$self->label]}</label>
@{[$self->render_input]}


EOF

    return $output;

}

sub render_input {
    my $self = shift;
    
    if ($self->type eq 'textarea') {
            my $value = $self->value() || '';
            Prophet::Util::escape_utf8(\$value);

return <<EOF;
<textarea @{[$self->render_name]} @{[$self->render_id]} @{[$self->render_class]} >@{[$value]}</textarea>
EOF
    } else {

return <<EOF;
<input type="@{[$self->type]}" @{[$self->render_name]} @{[$self->render_id]} @{[$self->render_class]} @{[$self->render_value]} />
EOF

    }

}



__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;
