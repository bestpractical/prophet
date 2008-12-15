package Prophet::Web::Result;
use Moose;
use MooseX::AttributeHelpers;

use Prophet::Web::FunctionResult;

=head1 NAME

Prophet::Web::Result

=head1 METHODS

=head1 DESCRIPTION

=cut

=head1 METHODS

=cut

has success => ( isa => 'Bool', is => 'rw');
has message => ( isa => 'Str', is => 'rw');
has functions => (
             metaclass => 'Collection::Hash',
             is        => 'rw',
             isa       => 'HashRef[Prophet::Web::FunctionResult]',
             default   => sub { {} },
             provides  => {
                 exists    => 'exists',
                 keys      => 'items',
                 get       => 'get',
                 set       => 'set',
             },

);


__PACKAGE__->meta->make_immutable;
no Moose;

1;

