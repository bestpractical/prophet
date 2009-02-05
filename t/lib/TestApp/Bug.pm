package TestApp::Bug;
use Any::Moose;
extends 'Prophet::Record';

has type => ( default => 'bug' );

use constant collection_class => 'TestApp::Bugs';

__PACKAGE__->register_reference( bugcatcher => 'TestApp::BugCatcher' );

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

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;
