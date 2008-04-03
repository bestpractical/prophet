use warnings;
use strict;

package Prophet::CLI;
use base qw/Class::Accessor/;
__PACKAGE__->mk_accessors(qw/type uuid _handle _resdb_handle/);

use Path::Class;
use Prophet;
use Prophet::Handle;
use Prophet::Record;
use Prophet::Collection;
use Prophet::Sync::Source;

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);
    $self->handle;
    $self->resdb_handle;
    return $self;
}

=head2 handle


=cut

sub handle {
    my $self = shift;
    unless ( $self->_handle ) {
        my $root = $ENV{'PROPHET_REPO'} || dir( $ENV{'HOME'}, '.prophet' );
        my $path = $ENV{'PROPHET_REPO_PATH'} || '_prophet';
        $self->_handle( Prophet::Handle->new( repository => $root, db_root => $path ) );
    }
    return $self->_handle();
}

sub resdb_handle {
    my $self = shift;
    unless ( $self->_resdb_handle ) {
        my $root = ( $ENV{'PROPHET_REPO'} || dir( $ENV{'HOME'}, '.prophet' ) ) . "_res";
        my $path = $ENV{'PROPHET_REPO_PATH'} || '_prophet';
        $self->_resdb_handle( Prophet::Handle->new( repository => $root, db_root => $path ) );
    }
    return $self->_resdb_handle();
}

=head2 record_cmd

Returns a closure that handles the subcommand for a particular type

=cut


our %CMD_MAP = (
    ls   => 'search',
    new  => 'create',
    edit => 'update',
    rm   => 'delete',
    del  => 'delete',
    list => 'search'
);

sub record_cmd {
    my ($self, $type) = @_;
    return sub {
        my $cmd = shift @ARGV or die "record subcommand required";
        $cmd =~ s/^--//g;
        $cmd = $CMD_MAP{$cmd} if exists $CMD_MAP{$cmd};
        my $func = $self->can("do_$cmd") or die "no such crecord ommand $cmd";
        $self->type($type);
        $self->parse_record_cmd_args();
        $func->($self);
    };
}

=head2 register_types TYPES

Register cmd_C<type> methods if the calling namespace that handles the cli command for each of the record type C<type>.

=cut

sub register_types {
    my $self = shift;
    my @types = (@_);
    
    my $calling_package = (caller)[0];
    for my $type (@types) {
        no strict 'refs';
         *{$calling_package."::cmd_".$type} = $self->record_cmd($type);
        }
}


=head2 parse_args

This routine pulls arguments passed on the command line out of ARGV and sticks them in L</args>. The keys have leading "--" stripped.


=cut

sub parse_args {
    my $self = shift;
    %{ $self->{'args'} } = @ARGV;
    for my $name ( keys %{ $self->{'args'} } ) {
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
        $self->uuid($uuid);
    }
    if ( $self->{args}->{type} ) {
        $self->type( delete $self->{args}->{'type'} );
    }
}

=head2 args [$ARGS]

Returns a reference to the key-value pairs passed in on the command line

If passed a hashref, sets the args to taht;

=cut

sub args {
    my $self = shift;
    
    $self->{'args'} = shift if $_[0]; 
    return $self->{'args'};

}

sub do_create {
    my $cli = shift;
    my $record = Prophet::Record->new( handle => $cli->handle, type => $cli->type );
    my ( $id, $results ) = $record->create( props => $cli->args );
    print "Created " . $cli->type . " " . $record->uuid . "\n";

}

sub do_search {
    my $cli = shift;

    my $regex;
    unless ( $regex = $cli->args->{regex} ) {
        die "Specify a regular expression and we'll search for records matching that regex";
    }

    my $records = Prophet::Collection->new( handle => $cli->handle, type => $cli->type );
    $records->matching(
        sub {
            my $item  = shift;
            my $props = $item->get_props;
            map { return 1 if $props->{$_} =~ $regex } keys %$props;
            return 0;
        }
    );

    for ( @{ $records->as_array_ref } ) {
        printf( "%s %s %s \n", $_->uuid, $_->prop('summary') || "(no summary)", $_->prop('status') || '(no status)' );
    }
}

sub do_update {
    my $cli = shift;

    my $record = Prophet::Record->new( handle => $cli->handle, type => $cli->type );
    $record->load( uuid => $cli->uuid );
    $record->set_props( props => $cli->args );

}

sub do_delete {
    my $cli = shift;

    my $record = Prophet::Record->new( handle => $cli->handle, type => $cli->type );
    $record->load( uuid => $cli->uuid );
    if ( $record->delete ) {
        print $record->type . " " . $record->uuid . " deleted.\n";
    } else {
        print $record->type . " " . $record->uuid . "could not be deleted.\n";
    }

}

sub do_show {
    my $cli = shift;

    my $record = Prophet::Record->new( handle => $cli->handle, type => $cli->type );
    $record->load( uuid => $cli->uuid );
    print "id: " . $record->uuid . "\n";
    my $props = $record->get_props();
    for ( keys %$props ) {
        print $_. ": " . $props->{$_} . "\n";
    }

}

sub do_merge {
    my $cli = shift;

    my $opts = $cli->args();

    warn $opts->{from};
    warn $opts->{to};
    
    my $source = Prophet::Sync::Source->new( { url => $opts->{'from'} } );
    my $target = Prophet::Sync::Source->new( { url => $opts->{'to'} } );

    if ( $target->uuid eq $source->uuid ) {
        fatal_error( "You appear to be trying to merge two identical replicas. "
                . "Either you're trying to merge a replica to itself or "
                . "someone did a bad job cloning your database" );
    }

    if ( !$target->accepts_changesets ) {
        fatal_error( $target->url . " does not accept changesets. Perhaps it's unwritable or something" );
    }

    $target->import_changesets(
        from      => $source,
        use_resdb => 1,
        $ENV{'PROPHET_RESOLVER'}
        ? ( resolver_class => 'Prophet::Resolver::' . $ENV{'PROPHET_RESOLVER'} )
        : ( ( $opts->{'prefer'} eq 'to'   ? ( resolver_class => 'Prophet::Resolver::AlwaysTarget' ) : () ),
            ( $opts->{'prefer'} eq 'from' ? ( resolver_class => 'Prophet::Resolver::AlwaysSource' ) : () )
        )
    );

    sub fatal_error {
        my $reason = shift;
        die $reason . "\n";

    }

}

1;
