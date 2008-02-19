use warnings;
use strict;

package TestApp::Bug;
use base qw/SVN::PropDB::Record/;


sub new { shift->SUPER::new( @_, type => 'bug') }


sub validate_name { 
    my $self = shift;
    my %args = (@_);

    return 1 if ($args{props}->{'name'} eq 'Jesse');

    return 0;

}


1;
