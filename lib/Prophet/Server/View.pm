#!/usr/bin/env perl
package Prophet::Server::View;
use strict;
use warnings;
use base 'Template::Declare';
use Template::Declare::Tags;

template '/' => sub {
    html {
        body {
            h1 { "Welcome!" }
        }
    }
};

template record_table => sub {
    my $self = shift;
    my $records = shift;

    html {
        body {
            table {
                my @items = $records ? $records->items : ();
                for my $record (sort { $a->luid <=> $b->luid } @items) {
                    my $type = $record->type;
                    my $uuid = $record->uuid;
                    my @atoms = $record->format_summary;

                    row {
                        attr { id => "$type-$uuid", class => "$type" };

                        for (@atoms) {
                            my $prop = $_->{prop};
                            cell {
                                attr {
                                    id    => "$type-$uuid-$prop",
                                    class => $prop,
                                };
                                outs $_->{value}
                            }
                        }
                    }
                }
            }
        }
    }
};

1;

