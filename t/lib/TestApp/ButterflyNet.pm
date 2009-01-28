package TestApp::ButterflyNet;
use Moose;
extends 'Prophet::Record';

has type => ( default => 'net' );

__PACKAGE__->meta->make_immutable;
no Moose;
1;
