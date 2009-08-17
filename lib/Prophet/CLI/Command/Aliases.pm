package Prophet::CLI::Command::Aliases;
use Any::Moose;
use Params::Validate qw/validate/;

extends 'Prophet::CLI::Command::Config';

sub ARG_TRANSLATIONS { shift->SUPER::ARG_TRANSLATIONS(), s => 'show' };

sub usage_msg {
    my $self = shift;
    my $cmd = $self->cli->get_script_name;

    return <<"END_USAGE";
usage: ${cmd}aliases [show]
       ${cmd}aliases edit [--global|--user]
       ${cmd}alias <alias text> [<text to translate to>]
END_USAGE
}

sub run {
    my $self     = shift;

    $self->print_usage if $self->has_arg('h');

    my $config = $self->config;

    my $template = $self->make_template;

    # alias.pull --from http://foo-bar.com/
    # add is the same as set
    if ( $self->context->has_arg('add') && !$self->has_arg('set') ) {
        $self->context->set_arg('set', $self->arg('add') )
    }

    if ( ! ( $self->has_arg('set') ||
             $self->has_arg('delete') || $self->has_arg('edit') ) ) {
        print $template. "\n";
        return;
    }
    else {
        $self->set_arg('set', 'alias.'.$self->arg('set'))
            if $self->has_arg('set');
        $self->set_arg('delete', 'alias.'.$self->arg('delete'))
            if $self->has_arg('delete');
        $self->SUPER::run(@_);
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
    elsif ( !$self->has_arg('edit') ) {
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
    #
    # one of the few ways to trigger this is to try to create an alias
    # that starts with a [ character
    if ($@) {
        chomp $@;
        my $error = "# Error: '$@'";
        $self->handle_template_errors(
            rtype => 'aliases',
            template_ref => $args{template},
            bad_template => $args{edited},
            errors_pattern => '',
            error => $error,
            old_errors => $self->old_errors,
        );
        $self->old_errors($error);
        return 0;
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

# override the messages from Config module with messages w/better context for
# Aliases
override delete_usage_msg => sub {
    my $self = shift;
    my $app_cmd = $self->cli->get_script_name;
    my $cmd = shift;

    qq{usage: ${app_cmd}${cmd} "alias text"\n};
};

override add_usage_msg => sub {
    my $self = shift;
    my $app_cmd = $self->cli->get_script_name;
    my ($cmd, $subcmd) = @_;

    qq{usage: ${app_cmd}$cmd $subcmd "alias text" "cmd to translate to"\n};
};

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;
