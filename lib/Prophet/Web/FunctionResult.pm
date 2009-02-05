package Prophet::Web::FunctionResult;
use Any::Moose;

=head1 NAME

=head1 METHODS

=head1 DESCRIPTION

=cut

=head1 METHODS

=cut

has class => ( isa => 'Str', is => 'rw');
has function_name => ( isa => 'Str', is => 'rw');
has record_uuid => (isa => 'Str|Undef', is => 'rw');
has success => (isa => 'Bool', is => 'rw');
has message => (isa => 'Str', is => 'rw');

has result => (
             is        => 'rw',
             isa       => 'HashRef',
             default   => sub { {} },
);

sub exists { exists $_[0]->result->{$_[1]} }
sub items  { keys %{ $_[0]->result } }
sub get    { $_[0]->result>{$_[1]} }
sub set    { $_[0]->result->{$_[1]} = $_[2] }

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

