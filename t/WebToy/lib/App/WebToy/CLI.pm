package App::WebToy::CLI;
use Any::Moose;
extends 'Prophet::CLI';

use App::WebToy;

has 'app_class' => (
    default => 'App::WebToy',
);


__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

