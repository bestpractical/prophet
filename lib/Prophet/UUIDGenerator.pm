package Prophet::UUIDGenerator;
use Data::UUID qw'NameSpace_DNS';
use Any::Moose;
use MIME::Base64::URLSafe;

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

sub create_safe_b64 {
    my $self = shift;
   $self->to_safe_b64($self->_uuid_generator->create); 
}

    sub create_safe_b64_from_url {
    my $self = shift;
    my $url = shift;
    local $!;
    $self->to_safe_b64($self->_uuid_generator->create_from_name(NameSpace_DNS, $url ));

}

sub from_safe_b64 {
    my $self = shift;
    my $uuid = shift;
    return urlsafe_b64decode($uuid);
}

sub to_safe_b64 {
    my $self = shift;
    my $uuid = shift;
    return urlsafe_b64encode($uuid);
}


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

