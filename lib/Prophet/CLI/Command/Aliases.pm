package Prophet::CLI::Command::Aliases;
use Any::Moose;
use Params::Validate qw/validate/;

extends 'Prophet::CLI::Command';
with 'Prophet::CLI::TextEditorCommand';

sub ARG_TRANSLATIONS { shift->SUPER::ARG_TRANSLATIONS(),  a => 'add', d => 'delete', s => 'show' };

sub run {
    my $self     = shift;
    my $template = $self->make_template;

    my $config = $self->app_handle->config;

    if ( $self->context->has_arg('show') ) {
        print $template. "\n";
        return;
    }

    # --add is the same as --set
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
                            filename => $config->replica_config_file,
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
                        filename => $config->replica_config_file,
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
                    filename => $config->replica_config_file,
                );
            }
            else {
                print "didn't find alias '$key'\n";
            }
        }

    }
    else {

        my $done = 0;

        while ( !$done ) {
            $done = $self->try_to_edit( template => \$template );
        }
    }
}

sub make_template {
    my $self = shift;

    my $content = '';
   
    $content .= "# Format: alias new_cmd = cmd\n"
      unless $self->context->has_arg('show');

    # get all settings records
    my $aliases = $self->app_handle->config->aliases;

    if ( $aliases ) {
        for my $key ( keys %$aliases ) {
            $content .= "alias $key = $aliases->{$key}\n";
        }
    }

    return $content;
}

sub parse_template {
    my $self     = shift;
    my $template = shift;

    my %parsed;
    for my $line ( split( /\n/, $template ) ) {
        if ( $line =~ /^\s*alias\s+(.+?)\s*=\s*(.+?)\s*$/ ) {
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

    my $aliases = $self->app_handle->config->aliases;
    my $c = $self->app_handle->config;

    my @added = grep { !$aliases->{$_} } sort keys %$config;

    my @changed =
      grep { $config->{$_} && $aliases->{$_} ne $config->{$_}
      } sort keys %$aliases;

    my @deleted = grep { !$config->{$_} } sort keys %$aliases;

    # TODO: 'set' all at once after implementing hash sets
    for my $add ( @added ) {
        print 'Added alias ' . "'$add' = '$config->{$add}'\n";
        $c->set(
            key => "alias.$add",
            value => $config->{$add},
            filename => $c->replica_config_file,
        );
    }

    for my $change (@changed) {
        print 'Changed alias ' . "'$change' from '$aliases->{$change}' to '$config->{$change}'\n";
        $c->set(
            key => "alias.$change",
            value => $config->{$change},
            filename => $c->replica_config_file,
        );
    }

    for my $delete ( @deleted ) {
        print "Deleted alias '$delete'\n";
        $c->set(
            key => "alias.$delete",
            filename => $c->replica_config_file,
        );
    }

    return 1;
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;
