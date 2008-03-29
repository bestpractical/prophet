use warnings;
use strict;

package Prophet::CLI;
use base qw/Class::Accessor/;
__PACKAGE__->mk_accessors(qw/type uuid _handle/);

use Path::Class;
use Prophet;
use Prophet::Handle;
use Prophet::Record;
use Prophet::Collection;


=head2 handle


=cut

sub handle {
    my $self = shift;
    unless ($self->_handle) {
    my $root = $ENV{'PROPHET_REPO'} || dir($ENV{'HOME'},'.prophet');
    my $path = $ENV{'PROPHET_REPO_PATH'} ||'_prophet';
    $self->_handle( Prophet::Handle->new( repository => $root, db_root => $path ));

    }
    return $self->_handle();
}



=head2 parse_args

This routine pulls arguments passed on the command line out of ARGV and sticks them in L</args>. The keys have leading "--" stripped.


=cut

sub parse_args {
    my $self = shift;
    %{$self->{'args'}} = @ARGV;
    for my $name ( keys %{$self->{'args'}} ) {
        die "$name doesn't look like --prop-name" if ( $name !~ /^--/ );
        $name =~ /^--(.*)$/;
        $self->{args}->{$1} = delete $self->{'args'}->{$name};
    }

}

=head2 parse_record_cmd_args

When working with individual records, it is often the case that we'll be expecting a --type argument and then a mess of other key-value pairs. 

=cut

sub parse_record_cmd_args {
    my $self = shift;
    $self->parse_args();

    if ( my $uuid = delete $self->{args}->{uuid} ) {
        $self->uuid( $uuid);
    }
    if ( $self->{args}->{type} ) {
        $self->type( delete $self->{args}->{'type'} );
    } else {
        die 'Node "--type" argument is mandatory';
    }
}

=head2 args

Returns a reference to the key-value pairs passed in on the command line

=cut


sub args {
    my $self = shift;
    return $self->{'args'};

}

1;
