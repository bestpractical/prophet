package Prophet::Web::Field;
use Moose;

has name   => ( isa => 'Str',             is => 'rw' );
has record => ( isa => 'Prophet::Record', is => 'rw' );
has prop  => ( isa => 'Str',             is => 'rw' );
has value  => ( isa => 'Str',             is => 'rw' );
has label => ( isa => 'Str', is => 'rw', default => sub {''});
has id    => ( isa => 'Str', is => 'rw' );
has class => ( isa => 'Str', is => 'rw' );
has value => ( isa => 'Str', is => 'rw' );

sub _render_attr {
    my $self = shift;
    my $attr = shift;
    my $value = $self->$attr() || return '';
    return $attr . '="' . $self->$attr() . '"';
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
<label @{[$self->render_name]}>@{[$self->label]}</label>
<input type="text" @{[$self->render_name]} @{[$self->render_id]} @{[$self->render_class]} @{[$self->render_value]} />

EOF

    return $output;

}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
