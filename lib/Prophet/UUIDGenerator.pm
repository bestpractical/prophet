package Prophet::UUIDGenerator;
use Data::UUID qw'NameSpace_DNS';
use Any::Moose;

our $UUIDGEN;

sub _uuid_generator {

        return $UUIDGEN ||= Data::UUID->new();
}

sub create_str {
    my $self = shift;
    return $self->_uuid_generator->create_str();
}

sub create_string_from_url {
    my $self = shift;
    my $url = shift;
    local $!;
    $self->_uuid_generator->create_from_name_str(NameSpace_DNS, $url )
}

sub from_string {
    my $self = shift;
    my $str = shift;
    $self->_uuid_generator->from_string($str);
}
 
sub to_string {
    my $self = shift;
    my $uuid = shift;
    $self->_uuid_generator->to_string($uuid);
}

sub from_safe_b64 {}

sub to_safe_b64 {}


=head1 NAME

Foo::Bar

=head1 METHODS

=head1 DESCRIPTION

=cut

=head1 METHODS

=cut




__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

