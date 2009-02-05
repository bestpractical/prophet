package Prophet::Meta::Types;
use Any::Moose;
use Any::Moose 'Util::TypeConstraints';

enum 'Prophet::Type::ChangeType' => qw/add_file add_dir update_file delete/;
enum 'Prophet::Type::FileOpConflict' => qw/delete_missing_file update_missing_file create_existing_file create_existing_dir/;

1;

__END__

=head1 NAME

Prophet::Meta::Types - extra types for Prophet

=head1 TYPES

=head2 Prophet::Type::ChangeType

A single change type: add_file, add_dir, update_file, delete.

=cut

