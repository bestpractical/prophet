package TestApp::ButterflyNet;
use Any::Moose;
extends 'Prophet::Record';

has type => ( default => 'net' );

__PACKAGE__->meta->make_immutable;
no Any::Moose;
1;
