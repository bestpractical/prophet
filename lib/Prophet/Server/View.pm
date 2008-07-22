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
            ul {
                for ( sort { $a->luid <=> $b->luid } $records->items ) {
                    li { $_->format_summary }
                }
            }
        }
    }
};

1;

