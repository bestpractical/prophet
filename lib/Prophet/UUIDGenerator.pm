package Prophet::UUIDGenerator;
use Any::Moose;
use MIME::Base64::URLSafe;

=head1 NAME

Prophet::UUIDGenerator

=head1 DESCRIPTION

Creates UUIDs using L<UUID::Tiny>.  Initially, it created v1 and v3
UUIDs; the new UUID scheme creates v4 and v5 UUIDs, instead.

=head1 METHODS

=head2 uuid_scheme

Gets or sets the UUID scheme; if 1, then creates v1 and v3 UUIDs (for
backward compatability with earlier versions of Prophet).  If 2, it
creates v4 and v5 UUIDs.

=cut

use UUID::Tiny ':std';

# uuid_scheme: 1 - v1 and v3 uuids.
#              2 - v4 and v5 uuids.

has uuid_scheme => (
    isa => 'Int',
    is  => 'rw'
);

=head2 create_str

Creates and returns v1 or v4 UUIDs, depending on L</uuid_scheme>.

=cut

sub create_str {
    my $self = shift;
    if ($self->uuid_scheme == 1 ){
        return create_uuid_as_string(UUID_V1);
    } elsif ($self->uuid_scheme == 2) {
        return create_uuid_as_string(UUID_V4);
    }
}

=head2 create_string_from_url URL

Creates and returns v3 or v5 UUIDs for the given C<URL>, depending on
L</uuid_scheme>.

=cut

sub create_string_from_url {
    my $self = shift;
    my $url = shift;
    local $!;
    if ($self->uuid_scheme == 1 ){
        # Yes, DNS, not URL. We screwed up when we first defined it
        # and it can't be safely changed once defined.
        create_uuid_as_string(UUID_V3, UUID_NS_DNS, $url);
    } elsif ($self->uuid_scheme == 2) {
        create_uuid_as_string(UUID_V5, UUID_NS_URL, $url);
    }
}

=head2 from_string

=cut

sub from_string {
    my $self = shift;
    my $str = shift;
    return string_to_uuid($str);
}

=head2 to_string

=cut

 
sub to_string {
    my $self = shift;
    my $uuid = shift;
    return uuid_to_string($uuid);
}

=head2 from_safe_b64

=cut

sub from_safe_b64 {
    my $self = shift;
    my $uuid = shift;
    return urlsafe_b64decode($uuid);
}

=head2 to_safe_b64

=cut

sub to_safe_b64 {
    my $self = shift;
    my $uuid = shift;
    return urlsafe_b64encode($self->from_string($uuid));
}

=head2 version

=cut

sub version {
    my $self = shift;
    my $uuid = shift;
    return version_of_uuid($uuid);
}

=head2 set_uuid_scheme

=cut

sub set_uuid_scheme {
    my $self = shift;
    my $uuid = shift;

    if ( $self->version($uuid) <= 3 ) {
        $self->uuid_scheme(1);
    } else {
        $self->uuid_scheme(2);
    }
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

