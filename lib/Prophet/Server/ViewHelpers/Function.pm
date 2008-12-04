package Prophet::Server::ViewHelpers::Function;

=head1 NAME

=head1 METHODS

=head1 DESCRIPTION

=cut

=head1 METHODS

=cut

use Template::Declare::Tags;

BEGIN {
 delete ${__PACKAGE__."::"}{meta};
 delete ${__PACKAGE__."::"}{with};
 }

use Moose;
use Moose::Util::TypeConstraints;


has record => (
    isa => 'Prophet::Record',
    is  => 'ro'
);

has action => (
    isa => ( enum [qw(create update delete)] ),
    is => 'ro'
);

has order => ( isa => 'Int', is => 'ro' );

has name => (
    isa => 'Str',
    is  => 'rw',

    #regex    => qr/^(?:|[\w\d]+)$/,
);





 sub new {
    my $self = shift->SUPER::new(@_);
    $self->name ( $self->record->uuid . "-" . $self->action ) unless ($self->name);
    return $self;
};

sub render {
    my $self = shift;
    my %bits =( 
        order  => $self->order,
        action => $self->action,
        uuid   => $self->record->uuid
    );

    my $string
        = "|"
        . join( "|", map { $bits{$_} ? $_ . "-" . $bits{$_} : '' } keys %bits )
        . "|";

    input {
        attr {
            type  => 'hidden',
            name  => "prophet-action|" . $self->name,
            value => $string
        };
    };
}


    __PACKAGE__->meta->make_immutable;
    no Moose;
1;

