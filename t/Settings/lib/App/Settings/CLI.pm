#!/usr/bin/env perl
package App::Settings::CLI;
use Any::Moose;
extends 'Prophet::CLI';

use App::Settings;

has '+app_class' => (
    default => 'App::Settings',
);


__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

