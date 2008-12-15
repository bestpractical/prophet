package App::WebToy::CLI;
use Moose;
extends 'Prophet::CLI';

use App::WebToy;

has 'app_class' => (
    default => 'App::WebToy',
);


__PACKAGE__->meta->make_immutable;
no Moose;

1;

