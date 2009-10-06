package Prophet::Server::ViewHelpers::Function;

use Template::Declare::Tags;
BEGIN { delete ${__PACKAGE__."::"}{meta}; 
 delete ${__PACKAGE__."::"}{with};
}

=head1 NAME

=head1 METHODS

=head1 DESCRIPTION

=cut

=head1 METHODS

=cut

use Any::Moose;
use Any::Moose 'Util::TypeConstraints';


has record => (
    isa => 'Prophet::Record',
    is  => 'ro'
);

has action => (
    isa => ( enum [qw(create update delete)] ),
    is => 'ro'
);

has order => ( isa => 'Int', is => 'ro' );

has validate => ( isa => 'Bool', is => 'rw', default => 1);
has canonicalize => ( isa => 'Bool', is => 'rw', default => 1);
has execute => ( isa => 'Bool', is => 'rw', default => 1);


has name => (
    isa => 'Str',
    is  => 'rw',

    #regex    => qr/^(?:|[\w\d]+)$/,
);





sub new {
    my $self = shift->SUPER::new(@_);
    $self->name ( ($self->record->loaded ? $self->record->uuid : 'new') . "-" . $self->action ) unless ($self->name);
    return $self;
}

sub render {
    my $self = shift;
    my %bits = ( 
        order  => $self->order,
        action => $self->action,
        type => $self->record->type,
        class => ref($self->record),
        uuid   => $self->record->uuid,
        validate => $self->validate,
        canonicalize => $self->canonicalize,
        execute => $self->execute
    );

    my $string
        = "|"
        . join( "|", map { $bits{$_} ? $_ . "=" . $bits{$_} : '' } keys %bits )
        . "|";

   
       outs_raw(qq{<input type="hidden" name="prophet-function-@{[$self->name]}" value="$string" />});
}


__PACKAGE__->meta->make_immutable(inline_constructor => 0);
no Any::Moose;
1;

