package Prophet::CLI::PublishCommand;
use Any::Moose 'Role';

use File::Temp ();

sub tempdir { my $dir = File::Temp::tempdir(CLEANUP => ! $ENV{PROPHET_DEBUG} ); return $dir; }

sub publish_dir {
    my $self = shift;
    my %args = @_;


    $args{from} .= '/';

    my @args;

    # Set directories to be globally +rx, files to be globally +r
    push @args, '--chmod=Da+rx,a+r';

    push @args, '--verbose' if $self->context->has_arg('verbose');

    # avoid edge cases when exporting replicas! still update files even
    # if they have the same size and time.
    # (latest-sequence-no is a file that can fall into this trap, since it's
    # ~easy for it to have the same size as it was previously and in test
    # cases we sometimes export to the same directory in quick succession)
    push @args, '--ignore-times';
    
    if ( $^O =~ /MSWin/ ) {
        require Win32;
        for (qw/from to/) {
            # convert old 8.3 name
            $args{$_} = Win32::GetLongPathName($args{$_});
            # cwrsync uses cygwin
            $args{$_} =~ s!^([A-Z]):!'/cygdrive/' . lc $1!eg;
            $args{$_} =~ s!\\!/!g;
            $args{$_} = q{"} . $args{$_} . q{"};
        }
    }
    
    push @args, '--recursive', '--' , $args{from}, $args{to};

    my $rsync = $ENV{RSYNC} || "rsync";

    my $ret = system($rsync, @args);

    if ($ret == -1) {
        die <<'END_DIE_MSG';
You must have 'rsync' installed to use this command.

If you have rsync but it's not in your path, set environment variable \$RSYNC
to the absolute path of your rsync executable.
END_DIE_MSG
    }

    return $ret;
}

no Any::Moose;

1;

