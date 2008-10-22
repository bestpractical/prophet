#!/usr/bin/env perl
package App::Settings::CLI;
use Moose;
extends 'Prophet::CLI';

use App::Settings;

has '+app_class' => (
    default => 'App::Settings',
);


__PACKAGE__->meta->make_immutable;
no Moose;

1;

