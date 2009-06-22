package Prophet::CLI::Command::Aliases;
use Any::Moose;
use Params::Validate qw/validate/;

extends 'Prophet::CLI::Command';
with 'Prophet::CLI::TextEditorCommand';

has config_filename => (
    is => 'rw',
    isa => 'Str',
    lazy => 1,
    default => sub {
        $_[0]->app_handle->config->replica_config_file;
    },
);

sub ARG_TRANSLATIONS { shift->SUPER::ARG_TRANSLATIONS(),  a => 'add', d => 'delete', s => 'show' };

sub run {
    my $self     = shift;

    my $config = $self->app_handle->config;

    if ($self->has_arg('global')) {
        $self->config_filename($config->global_file);
    }
    elsif ($self->has_arg('user')) {
        $self->config_filename($config->user_file);
    }

    my $template = $self->make_template;

    # add is the same as set
    if ( $self->context->has_arg('add') ) {
        $self->context->set_arg('set', $self->arg('add') )
    }

    if ( $self->has_arg('set') || $self->has_arg('delete') ) {

        if ( $self->has_arg('set') ) {
            my $value = $self->arg('set');
            if ( $value =~ /^\s*(.+?)\s*=\s*(.+?)\s*$/ ) {
                my $old = $config->get( key => "alias.$1" );
                if ( defined $old ) {
                    if ( $old ne $2 ) {
                        $config->set(
                            key => "alias.$1",
                            value => $2,
                            filename => $self->config_filename,
                        );
                        print
                          "changed alias '$1' from '$old' to '$2'\n";
                    }
                    else {
                        print "alias '$1 = $2' isn't changed, won't update\n";
                    }
                }
                else {
                    $config->set(
                        key => "alias.$1",
                        value => $2,
                        filename => $self->config_filename,
                    );
                    print "added alias '$1 = $2'\n";
                }
            }
        }
        elsif ( $self->has_arg('delete') ) {
            my $key = $self->arg('delete');

            if ( defined $config->get( key => "alias.$key" ) ) {
                print "deleted alias '$key = "
                      .$config->get( key => "alias.$key" )."'\n";

                $config->set(
                    key => "alias.$key",
                    filename => $self->config_filename,
                );
            }
            else {
                print "didn't find alias '$key'\n";
            }
        }

    }
    elsif ( $self->has_arg('edit') ) {
        my $done = 0;

        while ( !$done ) {
            $done = $self->try_to_edit( template => \$template );
        }
    }
    else {
        print $template. "\n";
        return;
    }

}

sub make_template {
    my $self = shift;

    my $content = '';
   
    $content .= $self->context->has_arg('edit') ?
        "# Editing aliases in config file ".$self->config_filename."\n\n"
        ."# Format: new_cmd = cmd\n"
        : "Active aliases for the current repository (including user-wide and"
        ." global\naliases if not overridden):\n\n";

    # get aliases from the config file we're going to edit, or all of them if
    # we're just displaying
    my $aliases = $self->has_arg('edit') ?
                  $self->app_handle->config->aliases( $self->config_filename )
                : $self->app_handle->config->aliases;

    if ( %$aliases ) {
        for my $key ( keys %$aliases ) {
            $content .= "$key = $aliases->{$key}\n";
        }
    }
    else {
        $content = "No aliases for the current repository.\n";
    }


    return $content;
}

sub parse_template {
    my $self     = shift;
    my $template = shift;

    my %parsed;
    for my $line ( split( /\n/, $template ) ) {
        if ( $line =~ /^\s*([^#].*?)\s*=\s*(.+?)\s*$/ ) {
            $parsed{$1} = $2;
        }
    }

    return \%parsed;
}

sub process_template {
    my $self = shift;
    my %args = validate( @_, { template => 1, edited => 1, record => 0 } );

    my $updated = $args{edited};
    my ($config) = $self->parse_template($updated);

    my $aliases = $self->app_handle->config->aliases( $self->config_filename );
    my $c = $self->app_handle->config;

    my @added = grep { !$aliases->{$_} } sort keys %$config;

    my @changed =
      grep { $config->{$_} && $aliases->{$_} ne $config->{$_}
      } sort keys %$aliases;

    my @deleted = grep { !$config->{$_} } sort keys %$aliases;

    # attempt to set all added/changed/deleted aliases at once
    my @to_set = (
        (map { { key => "alias.'$_'", value => $config->{$_} } }
            (@added, @changed)),
        (map { { key => "alias.'$_'" } } @deleted),
    );

    eval {
        $c->group_set(
            $self->config_filename,
            \@to_set,
        );
    };
    # if we fail, prompt the user to re-edit

    # one of the few ways to trigger this is to try to set a variable
    # that starts with a [ character

    # TODO: this doesn't really work correctly.
    # Also, handle_template_errors gives messages that are very
    # much tailored towards SD's ticket editing facility.
    # Should genericise that.
    if ($@) {
        warn $@;
        return $self->handle_template_errors(
            rtype => 'aliases',
            template_ref => $args{template},
            bad_template => $args{edited},
            error => "$@",
        );
    }
    # otherwise, print out what changed and return happily
    else {
        for my $add ( @added ) {
            print 'Added alias ' . "'$add' = '$config->{$add}'\n";
        }
        for my $change (@changed) {
            print "Changed alias '$change' from '$aliases->{$change}'"
                  ."to '$config->{$change}'\n";
        }
        for my $delete ( @deleted ) {
            print "Deleted alias '$delete'\n";
        }

        return 1;
    }
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;
