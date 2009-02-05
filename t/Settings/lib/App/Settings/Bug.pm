use warnings;
use strict;

package App::Settings::Bug;
use Any::Moose;
extends 'Prophet::Record';

use base qw/Prophet::Record/;


sub new { shift->SUPER::new( @_, type => 'bug' ) }

sub validate_prop_name {
    my $self = shift;
    my %args = (@_);

    return 1 if ( $args{props}->{'name'} eq 'Jesse' );

    return 0;

}

sub canonicalize_prop_email {
    my $self = shift;
    my %args = (@_);
    $args{props}->{email} = lc( $args{props}->{email} );
}

sub default_prop_status { 'new' }

1;
