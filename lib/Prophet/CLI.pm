package Prophet::CLI;
use Any::Moose;

use Prophet;
use Prophet::Replica;
use Prophet::CLI::Command;
use Prophet::CLI::Dispatcher;
use Prophet::CLIContext;

use List::Util 'first';
use Text::ParseWords qw(shellwords);

has app_class => (
    is      => 'rw',
    isa     => 'ClassName',
    default => 'Prophet::App',
);

has record_class => (
    is      => 'rw',
    isa     => 'ClassName',
    lazy    => 1,
    default => 'Prophet::Record',
);

has app_handle => (
    is      => 'rw',
    isa     => 'Prophet::App',
    lazy    => 1,
    handles => [qw/handle config/],
    default => sub {
        return $_[0]->app_class->new;
    },
);


has context => (
    is => 'rw',
    isa => 'Prophet::CLIContext',
    lazy => 1,
    default => sub {
        return Prophet::CLIContext->new( app_handle => shift->app_handle);
    }

);

has interactive_shell => ( 
    is => 'rw',
    isa => 'Bool',
    default => 0,
);

# default line length for CLI-related things that ought to wrap
use constant LINE_LENGTH => 80;

=head2 _record_cmd

handles the subcommand for a particular type

=cut

=head2 dispatcher_class -> Class

Returns the dispatcher used to dispatch command lines. You'll want to override
this in your subclass.

=cut

sub dispatcher_class { "Prophet::CLI::Dispatcher" }

=head2 run_one_command

Runs a command specified by commandline arguments given in an
ARGV-like array of argumnents and key value pairs . To use in a
commandline front-end, create a L<Prophet::CLI> object and pass in
your main app class as app_class, then run this routine.

Example:

 my $cli = Prophet::CLI->new({ app_class => 'App::SD' });
 $cli->run_one_command(@ARGV);

=cut

sub run_one_command {
    my $self = shift;
    my @args = (@_);

    # find the first alias that matches, rerun the aliased cmd
    # note: keys of aliases are treated as regex, 
    # we need to substitute $1, $2 ... in the value if there's any
    my $ori_cmd = join ' ', @args;

    if ($self->app_handle->local_replica_url) {
        my $aliases = $self->app_handle->config->aliases;
        while (my ($alias, $replacement) = each %$aliases ) {
            my $command = $self->_command_matches_alias(
                \@args, $alias, $replacement,
               ) || next;

            # we don't want to recursively call if people stupidly write
            # alias pull --local = pull --local
            next if ( join(' ', @$command) eq $ori_cmd );
            return $self->run_one_command(@$command);
        }
    }
    #  really, we shouldn't be doing this stuff from the command dispatcher
    $self->context( Prophet::CLIContext->new( app_handle => $self->app_handle ) );
    $self->context->setup_from_args(@args);
    my $dispatcher = $self->dispatcher_class->new( cli => $self );

    # Path::Dispatcher is string-based, so we need to join the args
    # hash with spaces before passing off (args with whitespace in
    # them are quoted, double quotes are escaped)
    my $dispatch_command_string = join(' ', map {
            s/"/\\"/g;  # escape double quotes
            /\s/ ? qq{"$_"} : $_;
        } @{ $self->context->primary_commands });
    my $dispatch = $dispatcher->dispatch( $dispatch_command_string );
    $self->start_pager();
    $dispatch->run($dispatcher);
    $self->end_pager();
}

sub _command_matches_alias {
    my $self  = shift;
    my @words = @{+shift};
    my @alias = shellwords(shift);
    my @expansion = shellwords(shift);

    # Compare @words against @alias
    return if(scalar(@words) < scalar(@alias));

    while(@alias) {
        if(shift @words ne shift @alias) {
            return;
        }
    }

    # @words now contains the remaining words given on the
    # command-line, and @expansion contains the words in the
    # expansion.

    if (first sub {m{\$\d+\b}}, @expansion) {
        # Expand $n placeholders
        for (@expansion) {
            s/\$(\d+)\b/$words[$1 - 1]||""/ge;
        }
        return [@expansion];
    } else {
        return [@expansion, @words];
    }
}

sub is_interactive {
  return -t STDIN && -t STDOUT;
}

sub get_pager {
    my $self = shift;
    return $ENV{'PAGER'} || `which less` || `which more`;
}

our $ORIGINAL_STDOUT;

sub start_pager {
    my $self = shift;
    my $content = shift;
    if (is_interactive() && !$ORIGINAL_STDOUT) {
        local $ENV{'LESS'} = '-FXe';
        local $ENV{'MORE'};
        $ENV{'MORE'} = '-FXe' unless $^O =~ /^MSWin/;

        my $pager = $self->get_pager();
        return unless $pager;
        open (my $cmd, "|-", $pager) || return;
        $|++;
        $ORIGINAL_STDOUT = *STDOUT;

        # $pager will be closed once we restore STDOUT to $ORIGINAL_STDOUT
        *STDOUT = $cmd;
    }
}

sub in_pager {
    return $ORIGINAL_STDOUT ? 1 :0;
}

sub end_pager {
    my $self = shift;
    return unless ($self->in_pager);
    *STDOUT = $ORIGINAL_STDOUT ;

    # closes the pager
    $ORIGINAL_STDOUT = undef;
}

=head2 get_script_name

Return the name of the script that was run. This is the empty string
if we're in a shell, otherwise the script name concatenated with
a space character. This is so you can just use this for e.g.
printing usage messages or help docs that might be run from either
a shell or the command line.

=cut

sub get_script_name {
    my $self = shift;
    return '' if $self->interactive_shell;
    require File::Spec;
    my ($cmd) = ( File::Spec->splitpath($0) )[2];
    return $cmd . ' ';
}

END {
   *STDOUT = $ORIGINAL_STDOUT if $ORIGINAL_STDOUT;
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

