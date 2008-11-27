package App::WebToy::Model::WikiPage;
use Moose;
extends 'Prophet::Record';
has type => ( default => 'wikipage');



sub declared_props {qw(title content tags mood)};

=head1 NAME

=head1 METHODS

=head1 DESCRIPTION

=cut

=head1 METHODS

=cut




__PACKAGE__->meta->make_immutable;
no Moose;

1;

