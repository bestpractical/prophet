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
                if (@items) {
                    my @headers = $items[0]->_parse_format_summary;
                    row {
                        th { outs_raw '&nbsp;' };

                        for (@headers) {
                            th { $_->{prop} }
                        }
                    }
                }

                for my $record (sort { $a->luid <=> $b->luid } @items) {
                    my $type = $record->type;
                    my $uuid = $record->uuid;
                    my @atoms = $record->format_summary;

                    row {
                        attr { id => "$type-$uuid", class => "$type" };

                        cell {
                            a {
                                attr { href => "$uuid.html" };
                                outs "(view)";
                            }
                        };

                        for (@atoms) {
                            my $prop = $_->{prop};
                            cell {
                                attr {
                                    class => "prop-$prop",
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

template record => sub {
    my $self = shift;
    my $record = shift;

    html {
        body {
            dl {
                dt { 'UUID' }
                dd { $record->uuid }
                dt { 'LUID' }
                dd { $record->luid };

                my $props = $record->get_props;
                for my $prop (sort keys %$props) {
                    dt { $prop }
                    dd { $props->{$prop} }
                }
            }
        }
    }
};

1;

