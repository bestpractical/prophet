package Prophet::CLI::PublishCommand;
use Any::Moose 'Role';

use File::Temp ();

sub tempdir { my $dir = File::Temp::tempdir(CLEANUP => ! $ENV{PROPHET_DEBUG} ); return $dir; }

sub publish_dir {
    my $self = shift;
    my %args = @_;


    $args{from} .= '/';

    my $rsync = $ENV{RSYNC} || "rsync";

    my @args;

    # chmod feature requires rsync >= 2.6.7
    my ($rsync_version) = ( (qx{$rsync --version})[0] =~ /version ([\d.]+) / );
    $rsync_version =~ s/[.]//g if $rsync_version; # kill dot separators in vnum
    if ( $rsync_version && $rsync_version < 267 ) {
        warn <<'END_WARNING';

W: rsync >= 2.6.7 is required in order to ensure the published replica has
W: the default permissions of the destination if they are more permissive
W: than the source replica's permissions. You may wish to upgrade your
W: rsync if possible. (I'll still publish, but your published replica
W: will have the same permissions as the source replica, which is probably
W: not what you want.)
END_WARNING
    }
    # Set directories to be globally +rx, files to be globally +r
    # note - this frobs the permissions on the *sending* side; the
    # receiving side's umask is still applied -- this option just
    # allows you to publish a replica stored in a private directory
    # and have it have the receiving end's default permissions, even
    # if those are more permissive than the original location
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

    my $ret = system($rsync, @args);

    if ($ret == -1) {
        die <<'END_DIE_MSG';
You must have 'rsync' installed to use this command.

If you have rsync but it's not in your path, set the environment variable
$RSYNC to the absolute path of your rsync executable.
END_DIE_MSG
    }
    elsif ($ret != 0) {
        die "Publish NOT completed! (rsync failed with return value $ret)\n";
    }
    else {
        return $ret;
    }
}

no Any::Moose;

1;

