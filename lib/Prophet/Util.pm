package Prophet::Util;
use strict;
use File::Basename;
use File::Spec;
use File::Path;
use Params::Validate;

=head2 updir PATH

Strips off the filename in the given path and returns the absolute
path of the remaining directory.

=cut

sub updir {
    my $self = shift;
    my $path = shift;
    my ($file, $dir, undef) = fileparse(File::Spec->rel2abs($path));
    return $dir;
}

=head2 slurp FILENAME

Reads in the entire file whose absolute path is given by FILENAME and
returns its contents, either in a scalar or in an array of lines,
depending on the context.

=cut

sub slurp {
    my $self = shift;
    my $abspath = shift;
    open (my $fh, "<", "$abspath") || die "$abspath: $!";

    my @lines = <$fh>;
    close $fh;

    return wantarray ? @lines : join('',@lines);
}

=head2 instantiate_record class => 'record-class-name', uuid => 'record-uuid', app_handle => $self->app_handle

Takes the name of a record class (must subclass L<Prophet::Record>), a uuid,
and an application handle and returns a new instantiated record object
of the given class.

=cut

sub instantiate_record {
    my $self = shift;
    my %args = validate(@_, { 
        class => 1,
        uuid => 1,
        app_handle => 1

        });
    die $args{class} ." is not a valid class " unless (UNIVERSAL::isa($args{class}, 'Prophet::Record'));
    my $object = $args{class}->new( uuid => $args{uuid}, app_handle => $args{app_handle});
    return $object;
}

=head2 escape_utf8 REF

Given a reference to a scalar, escapes special characters (currently just &, <,
>, (, ), ", and ') for use in HTML and XML.

Not an object routine (call as Prophet::Util::escape_utf8( \$scalar) ).

=cut

sub escape_utf8 {
    my $ref = shift;
    no warnings 'uninitialized';
    $$ref =~ s/&/&#38;/g;
    $$ref =~ s/</&lt;/g;
    $$ref =~ s/>/&gt;/g;
    $$ref =~ s/\(/&#40;/g;
    $$ref =~ s/\)/&#41;/g;
    $$ref =~ s/"/&#34;/g;
    $$ref =~ s/'/&#39;/g;
}


sub write_file {
    my $self = shift;
    my %args = validate( @_, { file => 1, content => 1 } );

    my ( undef, $parent, $filename ) = File::Spec->splitpath($args{file});
    unless ( -d $parent ) {
        eval { mkpath( [$parent] ) };
        if ( my $msg = $@ ) {
            die "Failed to create directory " . $parent . " - $msg";
        }
    }

    open( my $fh, ">", $args{file} ) || die $!;
    print $fh scalar( $args{'content'} )
        ; # can't do "||" as we die if we print 0" || die "Could not write to " . $args{'path'} . " " . $!;
    close $fh || die $!;
}

sub hashed_dir_name {
    my $hash = shift;

    return ( substr( $hash, 0, 1 ), substr( $hash, 1, 1 ), $hash );
}

1;
