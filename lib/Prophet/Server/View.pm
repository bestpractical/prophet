#!/usr/bin/env perl
package Prophet::Server::View;
use strict;
use warnings;
use base 'Template::Declare';
use Template::Declare::Tags;

template record_table => sub {
    my $self = shift;
    my $records = shift;

    html {
        body {
            table {
                for ( sort { $a->luid <=> $b->luid } $records->items ) {
                    my @atoms = $_->format_summary;
                    row {
                        cell { $_ } for @atoms;
                    }
                }
            }
        }
    }
};

1;

