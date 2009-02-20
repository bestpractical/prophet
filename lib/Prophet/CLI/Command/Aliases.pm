package Prophet::CLI::Command::Aliases;
use Any::Moose;
use Params::Validate qw/validate/;

extends 'Prophet::CLI::Command';
with 'Prophet::CLI::TextEditorCommand';

sub ARG_TRANSLATIONS { shift->SUPER::ARG_TRANSLATIONS(),  a => 'add', d => 'delete', s => 'show' };

sub run {
    my $self     = shift;
    my $template = $self->make_template;

    if ( $self->context->has_arg('show') ) {
        print $template. "\n";
        return;
    }

    # --add is the same as --set
    if ( $self->context->has_arg('add') ) {
        $self->context->set_arg('set', $self->arg('add') )
    }

    if ( $self->has_arg('set') || $self->has_arg('delete') ) {
        my $aliases = $self->app_handle->config->aliases;
        my $need_to_save;

        if ( $self->has_arg('set') ) {
            my $value = $self->arg('set');
            if ( $value =~ /^\s*(.+?)\s*=\s*(.+?)\s*$/ ) {
                if ( exists $aliases->{$1} ) {
                    if ( $aliases->{$1} ne $2 ) {
                        my $old = $aliases->{$1};
                        $aliases->{$1} = $2;
                        $need_to_save = 1;
                        print
                          "changed alias '$1' from '$old' to '$2'\n";
                    }
                    else {
                        print "alias '$1 = $2' isn't changed, won't update\n";
                    }
                }
                else {
                    $need_to_save = 1;
                    $aliases->{$1} = $2;
                    print "added alias '$1 = $2'\n";
                }
            }
        }
        elsif ( $self->has_arg('delete') ) {
            my $key = $self->arg('delete');
            if ( exists $aliases->{$key} ) {
                $need_to_save = 1;
                print "deleted alias '$key = $aliases->{$key}'\n";
                delete $aliases->{$key};
            }
            else {
                print "didn't find alias '$key'\n";
            }
        }

        if ($need_to_save) {
            $self->app_handle->config->save;
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

    my @added = grep { ! $aliases->{$_} } sort keys %$config;
    my @changed =
      grep { $config->{$_} && $aliases->{$_} ne $config->{$_} } sort keys %$aliases;
    my @deleted = grep { !$config->{$_} } sort keys %$aliases;

    for my $add ( @added ) {
        print 'Added alias ' . "'$add' = '$config->{$add}'\n";
    }

    for my $change (@changed) {
        print 'Changed alias ' . "'$change' from '$aliases->{$change}' to '$config->{$change}'\n";
    }

    for my $delete ( @deleted ) {
        print 'Deleted alias ' . "'$delete\n";
    }

    $self->app_handle->config->set(_aliases => $config );
    $self->app_handle->config->save;

    return 1;
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;
