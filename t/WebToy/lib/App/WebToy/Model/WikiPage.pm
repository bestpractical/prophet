package App::WebToy::Model::WikiPage;
use Any::Moose;
extends 'Prophet::Record';
has type => ( default => 'wikipage');



sub declared_props {qw(title content tags mood)};

=head1 NAME

=head1 METHODS

=head1 DESCRIPTION

=cut

=head1 METHODS

=cut


sub default_prop_content {
    'This page has no content yet';
}



__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

