package Prophet::Util;
use strict;
use File::Basename;

sub updir {
    my $self = shift;
    my $path = shift;
    my ($file, $dir, undef) = fileparse(File::Spec->rel2abs($path));
    return $dir;
}

sub slurp {
    my $self = shift;
    my $abspath = shift;
    open (my $fh, "<", "$abspath") || die $!;

    my @lines = <$fh>;
    close $fh;
    
    return wantarray ? @lines : join('',@lines);
}
1;
