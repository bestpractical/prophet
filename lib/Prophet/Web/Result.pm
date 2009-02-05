package Prophet::Web::Result;
use Any::Moose;

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
             is        => 'rw',
             isa       => 'HashRef',
             default   => sub { {} },
);

sub get    { $_[0]->functions->{$_[1]} }
sub set    { $_[0]->functions->{$_[1]} = $_[2] }
sub exists { exists $_[0]->functions->{$_[1]} }
sub items  { keys %{ $_[0]->functions } }

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

