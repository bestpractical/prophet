package Prophet::Util;
use strict;
use File::Basename;
use Params::Validate;

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

sub instantiate_record {
    my $self = shift;
    my %args = validate(@_, { 
        class => 1,
        uuid => 1,
        app_handle => 1

        });
    die $args{class} ." is not a valid class " unless (UNIVERSAL::isa($args{class}, 'Prophet::Record'));
    my $object = $args{class}->new( uuid => $args{uuid}, app_handle => $args{app_handle});
    die "Did not find the object " unless $object->uuid;
    return $object;
}

1;
