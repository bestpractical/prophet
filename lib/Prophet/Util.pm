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
    return $object;
}

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

1;
