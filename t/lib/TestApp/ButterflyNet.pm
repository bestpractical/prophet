package TestApp::ButterflyNet;
use Any::Moose;
extends 'Prophet::Record';

has type => (
    is      => 'bare',
    default => 'net',
);

__PACKAGE__->meta->make_immutable;
no Any::Moose;
1;
