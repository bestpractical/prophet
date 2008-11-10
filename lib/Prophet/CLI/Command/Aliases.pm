package Prophet::CLI::Command::Aliases;
use Moose;
use Params::Validate qw/validate/;

extends 'Prophet::CLI::Command';
with 'Prophet::CLI::TextEditorCommand';

sub run {
    my $self     = shift;
    my $template = $self->make_template;

    if ( $self->context->has_arg('show') ) {
        print $template. "\n";
        return;
    }

    my $done = 0;

    while ( !$done ) {
        $done = $self->try_to_edit( template => \$template );
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
no Moose;

1;
