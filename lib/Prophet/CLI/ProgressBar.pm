package Prophet::CLI::ProgressBar;
use Any::Moose 'Role';

use Time::Progress;
use Params::Validate ':all';

sub progress_bar { 
    my $self = shift;
    my %args = validate(@_, {max => 1, format => { optional =>1, default => "%30b %p %L (%E remaining)\r" }});
    my $bar = Time::Progress->new();


    $bar->attr(max => $args{max});
    my $bar_count = 0;
    my $format = $args{format};
    return sub {
       # disable autoflush to make \r work properly
       local $| = 1;
       print $bar->report(  $format, ++$bar_count );
    }
}

no Any::Moose 'Role';

1;

