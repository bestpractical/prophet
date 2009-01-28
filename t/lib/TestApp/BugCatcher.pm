package TestApp::BugCatcher;
use Moose;
extends 'Prophet::Record';

has type => ( default => 'bugcatcher' );

__PACKAGE__->register_reference( bugs => 'TestApp::Bugs', by => 'bugcatcher');
__PACKAGE__->register_reference( net => 'TestApp::ButterflyNet' );

__PACKAGE__->meta->make_immutable;
no Moose;
1;
