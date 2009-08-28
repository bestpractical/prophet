package Prophet::Replica::FS::Backend::File;
use Any::Moose;
use Fcntl qw/SEEK_END/;
use Params::Validate qw/validate validate_pos/;


has url => ( is => 'rw', isa => 'Str');
has fs_root => ( is => 'rw', isa => 'Str');

sub read_file {
	my $self = shift;
    my ($file) = validate_pos( @_, 1 );
        return eval {
            local $SIG{__DIE__} = 'DEFAULT';
            Prophet::Util->slurp(
                File::Spec->catfile( $self->fs_root => $file ) );
        };
}

sub read_file_range {
    my $self = shift;
    my %args = validate( @_, { path => 1, position => 1, length => 1 } );

    if ($self->fs_root) {
        my $f = File::Spec->catfile( $self->fs_root => $args{path} );
        return unless -e $f;
        if ( $^O =~ /MSWin/ ) {
            # XXX by sunnavy
# the the open, seek and read below doesn't work on windows, at least with
# strawberry perl 5.10.0.6 on windows xp
#
# the differences:
# with substr, I got:
# 0000000: 0000 0004 ecaa d794 a5fe 8c6f 6e85 0d0a  ...........on...
# 0000010: 7087 f0cf 1e92 b50d f9                   p........
# 
# the read, I got
# 0000000: 0000 04ec aad7 94a5 fe8c 6f6e 850d 0d0a  ..........on....
# 0000010: 7087 f0cf 1e92 b50d f9                   p........
# 
# seems with read, we got an extra 0d, I dont' know why yet :/
            my $content = Prophet::Util->slurp( $f );
                return substr($content, $args{position}, $args{length});
        }
        else {
            open( my $index, "<:bytes", $f ) or return;
            seek( $index, $args{position}, SEEK_END ) or return;
            my $record;
            read( $index, $record, $args{length} ) or return;
            return $record;
        }
    }
    else {
        # XXX: do range get if possible
        my $content = $self->lwp_get( $self->url . "/" . $args{path} );
        return substr($content, $args{position}, $args{length});
    }

}

sub write_file {
    my $self = shift;
    my %args = validate( @_, { path => 1, content => 1 } );

    my $file = File::Spec->catfile( $self->fs_root => $args{'path'} );
    Prophet::Util->write_file( file => $file, content => $args{content});

}

sub append_to_file {
	my $self = shift;
	my ($filename, $content) = validate_pos(@_, 1,1 );
    open( my $file,
        ">>" . File::Spec->catfile( $self->fs_root => $filename)
    ) || die $!;
    print $file $content || die $!;
	close $file;
}

sub file_exists {
	my $self = shift;
    my ($file) = validate_pos( @_, 1 );


    my $path = File::Spec->catfile( $self->fs_root, $file );
    if    ( -f $path ) { return 1 }
    elsif ( -d $path ) { return 2 }
    else               { return 0 }


}


sub can_read { 1;

}

sub can_write { 1;

}

1;
