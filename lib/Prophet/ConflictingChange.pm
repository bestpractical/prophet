
use warnings;
use strict;

package Prophet::ConflictingChange;
use Prophet::ConflictingPropChange;

use base qw/Class::Accessor/;
use Storable 'dclone';

# change_type is one of: add_file add_dir update delete
__PACKAGE__->mk_accessors(qw/node_type node_uuid source_node_exists target_node_exists change_type file_op_conflict/);

=head2 prop_conflicts

Returns a reference to an array of Prophet::ConflictingPropChange objects

=cut

sub prop_conflicts {
    my $self = shift;

    $self->{'prop_conflicts'} ||= [];
    return $self->{prop_conflicts};

}

=head2 neutralize

Returns the clone of the changeset, except hte propchanges will have target_value and source_new_value as a sorted "choices" field of arrayref.

=cut

sub neutralize {
    my $self = shift;
    my $struct = dclone($self);
    for (@{$struct->{prop_conflicts}}) {
        $_->{choices} = [ sort (delete $_->{source_new_value}, delete $_->{target_value}) ];
    }
    return $struct;
}

=head2 cas_key

returned the key signatured by the content of the conflicting change.

=cut

use YAML::Syck;
use Digest::MD5 'md5_hex';

sub cas_key {
    my $self = shift;
    return md5_hex(YAML::Syck::Dump($self->neutralize));
}

1;
