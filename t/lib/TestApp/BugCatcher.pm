package TestApp::BugCatcher;
use Any::Moose;
extends 'Prophet::Record';

has type => ( default => 'bugcatcher' );

__PACKAGE__->register_reference( bugs => 'TestApp::Bugs', by => 'bugcatcher');
__PACKAGE__->register_reference( net => 'TestApp::ButterflyNet' );

__PACKAGE__->meta->make_immutable;
no Any::Moose;
1;
