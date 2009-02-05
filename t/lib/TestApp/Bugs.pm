package TestApp::Bugs;
use Any::Moose;
extends 'Prophet::Collection';

use constant record_class => 'TestApp::Bug';

__PACKAGE__->meta->make_immutable;
no Any::Moose;
1;
