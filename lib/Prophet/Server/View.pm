use strict;
use warnings;

package Prophet::Server::View;
use base 'Template::Declare';

use Template::Declare::Tags;
use Prophet::Server::ViewHelpers;
use Params::Validate;
use Prophet::Web::Menu;

our $APP_HANDLE;
sub app_handle {
    my $self = shift;
    $APP_HANDLE = shift if (@_);
    return $APP_HANDLE;
}

our $CGI;
sub cgi {
    my $self = shift;
    $CGI = shift if (@_);
    return $CGI;
}

our $MENU;
sub nav {
    my $self = shift;
    $MENU = shift if (@_);
    return $MENU;
}

our $SERVER;
sub server {
    my $self = shift;
    $SERVER = shift if (@_);
    return $SERVER;

};



template '_prophet_autocompleter' => sub {
        my $self = shift;
        my %args;
        for (qw(q function record type class prop)) {
            $args{$_} = $self->cgi->param($_);
        }
        my $obj = Prophet::Util->instantiate_record(
            class      => $self->cgi->param('class'),
            uuid       => $self->cgi->param('uuid'),
            app_handle => $self->app_handle
        );

        outs_raw(
        $obj->prop($self->cgi->param('prop')). " | ".
        $obj->prop($self->cgi->param('prop'))
        );

};



sub default_page_title { 'Prophet' }

template head => sub {
    my $self = shift;
    my $args = shift;
    head {
        title { shift @$args };
        for ( $self->server->css ) {
            link { { rel is 'stylesheet', href is $_, type is "text/css", media is 'screen'} };
        }
        for ( $self->server->js ) {
            script { { src is $_, type is "text/javascript" } };
        }
    }

};

template footer => sub {};
template header => sub {
    my $self = shift;
    my $args = shift;
    my $title = shift @$args;
if ($self->nav) {
    div { { class is 'page-nav'};
        outs_raw($self->nav->render_as_menubar) 
    };
    }
    h1 { $title };
};


template '/' => page {
            h1 { "This is a Prophet replica!" }
};

sub record_table {
    my %args = validate(@_, {
        records    => 1,
        url_prefix => { default => '' },
    });

    my $records = $args{records};
    my $prefix  = $args{url_prefix};

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
                                    href => "$prefix$uuid.html",
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

template record_table => 

        page {
    my $self = shift;
    my $records = shift;
            record_table(records => $records);
};

template record => page {
    my $self = shift;
    my $record = shift;

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
            };

            hr {}
            h3 { "History" };

            show record_changesets => $record;

            # linked collections
            for my $method ($record->collection_reference_methods) {
                my $collection = $record->$method;
                next if $collection->count == 0;

                my $type = $collection->record_class->type;

                hr {}
                h3 { "Linked $type records" }

                record_table(
                    records    => $collection,
                    url_prefix => "../$type/",
                );
            }

};

private template record_changesets => sub {
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

