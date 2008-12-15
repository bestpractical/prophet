package Prophet::Web::FunctionResult;
use Moose;

=head1 NAME

=head1 METHODS

=head1 DESCRIPTION

=cut

=head1 METHODS

=cut

has class => ( isa => 'Str', is => 'rw');
has function_name => ( isa => 'Str', is => 'rw');
has record_uuid => (isa => 'Str', is => 'rw');
has success => (isa => 'Bool', is => 'rw');
has message => (isa => 'Str', is => 'rw');

has result => (
             metaclass => 'Collection::Hash',
             is        => 'rw',
             isa       => 'HashRef[Str]',
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

