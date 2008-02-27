use warnings;
use strict;

package TestApp::Bug;
use base qw/Prophet::Record/;


sub new { shift->SUPER::new( @_, type => 'bug') }


sub validate_name { 
    my $self = shift;
    my %args = (@_);

    return 1 if ($args{props}->{'name'} eq 'Jesse');

    return 0;

}

sub canonicalize_email {
    my $self = shift;
    my %args = (@_);
    $args{props}->{email} = lc($args{props}->{email});
}

1;
