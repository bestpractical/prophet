package TestApp::Bugs;
use Moose;
extends 'Prophet::Collection';

use constant record_class => 'TestApp::Bug';

__PACKAGE__->meta->make_immutable;
no Moose;
1;
