#!/usr/bin/env perl
package Prophet::Server::View;
use strict;
use warnings;
use base 'Template::Declare';
use Template::Declare::Tags;
use Params::Validate;

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
            hr {}
            h3 { "History" };

            show record_changesets => $record;
        }
    }
};

template record_changesets => sub {
    my $self = shift;
    my $record = shift;
    my $uuid = $record->uuid;

    ol {
        for my $change ($record->changes) {
            my @prop_changes = $change->prop_changes;
            next if @prop_changes == 0;

            if (@prop_changes == 1) {
                li { $prop_changes[0]->summary };
                next;
            }

            li {
                ul {
                    for my $prop_change (@prop_changes) {
                        li {
                            outs $prop_change->summary;
                        }
                    }
                }
            }
        }
    }
};

sub generate_changeset_feed {
    my $self = shift;
    my %args = validate(@_, {
        handle => 1,
        title  => 0,
    });

    my $handle = $args{handle};
    my $title = $args{title} || 'Prophet replica ' . $handle->uuid;

    require XML::Atom::SimpleFeed;

    my $feed = XML::Atom::SimpleFeed->new(
        id     => "urn:uuid:" . $handle->uuid,
        title  => $title,
        author => $ENV{USER},
    );

    my $newest = $handle->latest_sequence_no;
    my $start = $newest - 20;
    $start = 0 if $start < 0;

    $handle->traverse_changesets(
        after    => $start,
        callback => sub {
            my $change = shift;

            $feed->add_entry(
                title => 'Changeset ' . $change->sequence_no,
                # need uuid or absolute link :(
                category => 'Changeset',
            );
        },
    );

    return $feed;
}

1;

