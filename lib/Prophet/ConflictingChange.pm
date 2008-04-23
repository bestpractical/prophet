use warnings;
use strict;

package Prophet::ConflictingChange;
use Prophet::ConflictingPropChange;

use base qw/Class::Accessor/;
use JSON qw'to_json';
use Digest::SHA1 'sha1_hex';

# change_type is one of: add_file add_dir update delete
__PACKAGE__->mk_accessors(qw/record_type record_uuid source_record_exists target_record_exists change_type file_op_conflict/);

=head2 prop_conflicts

Returns a reference to an array of Prophet::ConflictingPropChange objects

=cut

sub prop_conflicts {
    my $self = shift;

    $self->{'prop_conflicts'} ||= [];
    return $self->{prop_conflicts};

}


sub as_hash {
    my $self = shift;
    my $struct = {
        map { $_ => $self->$_() } (
            qw/record_type record_uuid source_record_exists target_record_exists change_type file_op_conflict/
        )
    };
    for ( @{ $self->prop_conflicts } ) {
        push @{ $struct->{'prop_conflicts'} }, $_->as_hash;
    }

    return $struct;
}

=head2 fingerprint

Returns a fingerprint of the content of this conflicting change

=cut


sub fingerprint {
    my $self = shift;

    my $struct = $self->as_hash;
    for ( @{ $struct->{prop_conflicts} } ) {
        $_->{choices} = [ sort ( delete $_->{source_new_value}, delete $_->{target_value} ) ];
    }

    return  sha1_hex(to_json($struct, {utf8 => 1, canonical => 1}));


}
1;
