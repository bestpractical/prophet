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

                        for my $i (0 .. $#atoms) {
                            my $atom = $atoms[$i];
                            my $prop = $atom->{prop};

                            cell {
                                attr {
                                    class => "prop-$prop",
                                };

                                if ($i == 0) {
                                    a {
                                        attr {
                                            href => "$uuid.html",
                                        };
                                        outs $atom->{value};
                                    }
                                }
                                else {
                                    outs $atom->{value};
                                }
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
            p {
                a {
                    attr {
                        href => "index.html",
                    };
                    outs "index";
                }
            }
            hr {}
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

