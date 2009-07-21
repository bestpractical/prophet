package Prophet::CLI::Command::Config;
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

has old_errors => (
    is => 'rw',
    isa => 'Str',
    default => '',
);

sub ARG_TRANSLATIONS { shift->SUPER::ARG_TRANSLATIONS(),  a => 'add', d => 'delete', s => 'show' };

sub run {
    my $self = shift;

    my $config = $self->config;

    if ($self->has_arg('global')) {
        $self->config_filename($config->global_file);
    }
    elsif ($self->has_arg('user')) {
        $self->config_filename($config->user_file);
    }

    # add is the same as set
    if ( $self->context->has_arg('add') ) {
        $self->context->set_arg('set', $self->arg('add') )
    }

    if ( $self->has_arg('set') || $self->has_arg('delete') ) {

        if ( $self->has_arg('set') ) {
            my $value = $self->arg('set');
            if ( $value =~ /^\s*(.+?)\s*=\s*(.+?)\s*$/ ) {
                $config->set(
                    key => $1,
                    value => $2,
                    filename => $self->config_filename,
                );
            }
            # no value given, just print the current value
            else {
                print $config->get( key => $self->arg('set') ) . "\n";
            }
        }
        elsif ( $self->has_arg('delete') ) {
            my $key = $self->arg('delete');

            $config->set(
                key => $key,
                filename => $self->config_filename,
            );
        }

    }
    elsif ( $self->has_arg('edit') ) {
        my $done = 0;

        die "You don't have write permissions on "
            .$self->config_filename.", can't edit!\n"
            if (-e $self->config_filename && ! -w $self->config_filename)
                || ! -w (File::Spec->splitpath($self->config_filename))[1];
        my $template = $self->make_template;

        while ( !$done ) {
            $done = $self->try_to_edit( template => \$template );
        }
    }
    else {
        print "Configuration:\n\n";
        my @files =@{$config->config_files};
        if (!scalar @files) {
            print $self->no_config_files;
            return;
        }
        print "Config files:\n\n";
        for my $file (@files) {
            print "$file\n";
        }
        print "\nYour configuration:\n\n";
        $config->dump;
    }
}

sub make_template {
    my $self = shift;

    return -f $self->config_filename
            ? Prophet::Util->slurp( $self->config_filename ) : '';
}

sub process_template {
    my $self = shift;
    my %args = validate( @_, { template => 1, edited => 1, record => 0 } );

    # Attempt parsing the config. If we're good, remove any previous error
    # sections, write to disk and load.
    eval {
        $self->config->parse_content(
            content => $args{edited},
            error => sub {
                Config::GitLike::error_callback( @_, filename =>
                    $self->config_filename );
            },
        );
    };
    if ($@) {
        chomp $@;
        my @error_lines = split "\n", $@;
        my $error = join "\n", map { "# Error: '$_'" } @error_lines;
        $self->handle_template_errors(
            rtype => 'configuration',
            template_ref => $args{template},
            bad_template => $args{edited},
            errors_pattern => '',
            error => $error,
            old_errors => $self->old_errors,
        );
        return 0;
    }
    my $old_errors = $self->old_errors;
    Prophet::Util->write_file(
        file => $self->config_filename,
        content => $args{edited},
    );
    return 1;
}

sub no_config_files {
    my $self = shift;
    return "No configuration files found. "
         . " Either create a file called
         '".$self->handle->app_handle->config->replica_config_file.
         "' or set the PROPHET_APP_CONFIG environment variable.\n\n";
}

sub parse_cli_arg {
    my $self = shift;
    my ($cmd, $arg) = @_;

    if ( $arg =~ /^show\b/ ) {
        $self->context->set_arg(show => 1);
    }
    elsif ( $arg =~ /^edit\b/ ) {
        $self->context->set_arg(edit => 1);
    }
    # arg *might* be quoted
    elsif ( $arg =~ /^delete\s+"?([^"]+)"?/ ) {
        $self->context->set_arg(delete => $1);
    }
    # prophet alias "foo bar" = "foo baz"
    # prophet alias foo = bar
    # prophet alias add foo bar = "bar baz"
    # prophet alias add foo bar = bar baz
    elsif ( $arg =~
        /^(?:add |set )?\s*(?:(?:"([^"]+)"|([^"]+))\s+=\s+(?:"([^"]+)"|([^"]+)))$/ ) {
        my ($orig, $new) = grep { defined } ($1, $2, $3, $4);
        $orig = "'$orig'" if $cmd =~ /alias/ && $orig =~ /\./;
        $self->context->set_arg(set => "$orig=$new");
    }
    # prophet alias "foo = bar"
    # prophet alias "foo bar = foo baz"
    elsif ( $arg =~ /^(?:add |set )?\s*"([^"]+=[^"]+)"$/ ) {
        $self->context->set_arg(set => $1);
    }
    # alternate syntax (preferred):
    # prophet alias "foo bar" "bar baz", prophet alias foo "bar baz",
    # prophet alias foo bar, etc.
    elsif ( $arg =~ /^(?:add |set )?\s*(?:"([^"]+)"|([^"\s]+))(?:\s+(?:"([^"]+)"|([^"\s]+)))?/ ) {
        my ($orig, $new) = grep { defined } ($1, $2, $3, $4);
        $orig = "'$orig'" if $cmd =~ /alias/ && $orig =~ /\./;
        if ( $new ) {
            $self->context->set_arg(set => "$orig=$new");
        }
        else {
            $self->context->set_arg(set => $orig);
        }
    }
    else {
        die 'no idea what you mean, sorry';
    }
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

