use strict;
use warnings;

package Prophet::Meta::Types;
use Moose::Util::TypeConstraints;

enum 'Prophet::Type::ChangeType' => qw/add_file add_dir update_file delete/;

1;

__END__

=head1 NAME

Prophet::Meta::Types - extra types for Prophet

=head1 TYPES

=head2 Prophet::Type::ChangeType

A single change type: add_file, add_dir, update_file, delete.

=cut

