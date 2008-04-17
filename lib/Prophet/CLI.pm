use warnings;
use strict;

package Prophet::CLI;
use base qw/Class::Accessor/;
__PACKAGE__->mk_accessors(qw/app_class record_class type uuid app_handle/);

use Prophet;
use Prophet::Record;
use Prophet::Collection;
use Prophet::Replica;

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);
    $self->record_class('Prophet::Record') unless $self->record_class;
    
    if($self->app_class) {
        my $replica_class = $self->app_class."::Replica";
        my $except = $replica_class."::(.*)::";
        Module::Pluggable->import( search_path => $replica_class, sub_name => 'app_replica_types', require => 1, except => qr/$except/);
        Prophet::Replica->register_replica_scheme(scheme => $_->scheme, class => $_) for ( __PACKAGE__->app_replica_types);
    }


    my $app_class = $self->app_class || 'Prophet::App';
    $app_class->require();# unless exists $INC{$app_class_path};
    $self->app_handle($app_class->new);
    return $self;
}

=head2 _record_cmd

handles the subcommand for a particular type

=cut

our %CMD_MAP = (
    ls   => 'search',
    new  => 'create',
    edit => 'update',
    rm   => 'delete',
    del  => 'delete',
    list => 'search'
);

sub _handle_reference_command {
    my ( $self, $class, $ref_spec ) = @_;

    # turn uuid arg into a prop at ref'ed class
    my $by_type = $ref_spec->{by};
    @ARGV = map { s/--uuid/--$by_type/; $_ } @ARGV;
    unshift @ARGV, '--search', '--regex', '.';    # list only for now
    $self->_record_cmd( $ref_spec->{type}->record_type, $ref_spec->{type} );
}

sub _record_cmd {
    my ( $self, $type, $record_class ) = @_;
    my $cmd = shift @ARGV or die "record subcommand required";
    $cmd =~ s/^--//g;

    $record_class->require || die $@;
    if ( $record_class->REFERENCES->{$cmd} ) {
        return $self->_handle_reference_command( $record_class, $record_class->REFERENCES->{$cmd} );
    }
    $cmd = $CMD_MAP{$cmd} if exists $CMD_MAP{$cmd};
    my $func = $self->can("do_$cmd") or Carp::confess "no such record command $cmd";
    if ($record_class) {
        $self->record_class($record_class);
    } else {
        $self->record_class('Prophet::Record');
        $self->type($type);
    }
    $self->parse_record_cmd_args();
    $func->($self);
}

=head2 register_types TYPES

Register cmd_C<type> methods if the calling namespace that handles the cli command for each of the record type C<type>.

=cut

sub register_types {
    my $self       = shift;
    my $model_base = shift;
    my @types      = (@_);

    my $calling_package = (caller)[0];
    for my $type (@types) {
        no strict 'refs';
        my $class = $model_base . '::' . ucfirst($type);
        $class->require;
        *{ $calling_package . "::cmd_" . $type } = sub {
            $self->_record_cmd( $type => $class );
        };
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

sub _get_record {
    my $self = shift;
    return $self->record_class->new(
        {   handle => $self->app_handle->handle,
            type   => $self->type,
        }
    );
}

sub do_create {
    my $self   = shift;
    my $record = $self->_get_record;

    $record->create( props => $self->args );

    print "Created " . $record->record_type . " " . $record->uuid . "\n";

}

sub do_search {
    my $self = shift;

    my $regex;
    unless ( $regex = $self->args->{regex} ) {
        die "Specify a regular expression and we'll search for records matching that regex";
    }
    my $record = $self->_get_record;
    $record->collection_class->require;
    my $records = $record->collection_class->new( handle => $self->app_handle->handle, type => $self->type );
    $records->matching(
        sub {
            my $item  = shift;
            my $props = $item->get_props;
            map { return 1 if $props->{$_} =~ $regex } keys %$props;
            return 0;
        }
    );

    for ( sort { $a->uuid cmp $b->uuid } @{ $records->as_array_ref } ) {
        if($_->summary_props) {
        print $_->format_summary . "\n";
        } else {
            # XXX OLD HACK TO MAKE TESTS PASS
        printf ("%s %s %s \n", $_->uuid, $_->prop( 'summary')||"(no summary)", $_->prop('status')||'(no status)');
        }
    }
}

sub do_update {
    my $self = shift;

    my $record = $self->_get_record;
    $record->load( uuid => $self->uuid );
    $record->set_props( props => $self->args );

}

sub do_delete {
    my $self = shift;

    my $record = $self->_get_record;
    $record->load( uuid => $self->uuid );
    if ( $record->delete ) {
        print $record->type . " " . $record->uuid . " deleted.\n";
    } else {
        print $record->type . " " . $record->uuid . "could not be deleted.\n";
    }

}

sub do_show {
    my $self = shift;

    my $record = $self->_get_record;
    $record->load( uuid => $self->uuid );
    print "id: " . $record->uuid . "\n";
    my $props = $record->get_props();
    for ( keys %$props ) {
        print $_. ": " . $props->{$_} . "\n";
    }

}

sub do_push {
    my $self         = shift;
    my $replica_type = $ENV{'PROPHET_REPLICA_TYPE'} || 'svn';
    my $source_me    = Prophet::Replica->new( { url => $replica_type. ":file://" . $self->app_handle->handle->fs_root } );
    my $other        = shift @ARGV;
    my $source_other = Prophet::Replica->new( { url => $other } );
    my $resdb        = $source_me->import_resolutions_from_remote_replica( from => $source_other );

    $self->_do_merge( $source_me, $source_other );
}

sub do_export {
    my $self      = shift;
    my $replica_type = $ENV{'PROPHET_REPLICA_TYPE'} || 'svn';
    my $source_me = Prophet::Replica->new( { url => $replica_type.":file://" . $self->app_handle->handle->fs_root } );
    my $path      = $self->args->{'path'};
    $source_me->export_to( path => $path );
}

sub do_pull {
    my $self         = shift;
    my $replica_type = $ENV{'PROPHET_REPLICA_TYPE'} || 'svn';
    my $source_me    = Prophet::Replica->new( { url => $replica_type. ":file://" . $self->app_handle->handle->fs_root } );
    my $other        = shift @ARGV;
    my $source_other = Prophet::Replica->new( { url => $other } );
    my $resdb        = $source_me->import_resolutions_from_remote_replica( from => $source_other );

    $self->_do_merge( $source_other, $source_me );

}

sub do_server {
    my $self = shift;

    my $opts = $self->args();
    require Prophet::Server::REST;
    my $server = Prophet::Server::REST->new( $opts->{'port'} || 8080 );
    $server->prophet_handle( $self->app_handle->handle );
    $server->run;
}

sub do_merge {
    my $self = shift;

    my $opts = $self->args();


    my $source = Prophet::Replica->new( { url => $opts->{'from'} } );
    my $target = Prophet::Replica->new( { url => $opts->{'to'} } );

    $target->import_resolutions_from_remote_replica( from => $source );

    $self->_do_merge( $source, $target );
}

sub _do_merge {
    my ( $self, $source, $target ) = @_;
    if ( $target->uuid eq $source->uuid ) {
        fatal_error( "You appear to be trying to merge two identical replicas. "
                . "Either you're trying to merge a replica to itself or "
                . "someone did a bad job cloning your database" );
    }

    my $opts = $self->args();

    $opts->{'prefer'} ||= 'none';

    if ( !$target->can_write_changesets) {
        fatal_error( $target->url . " does not accept changesets. Perhaps it's unwritable or something" );
    }

    $target->import_changesets(
        from  => $source,
        resdb => $self->app_handle->resdb_handle,
        $ENV{'PROPHET_RESOLVER'}
        ? ( resolver_class => 'Prophet::Resolver::' . $ENV{'PROPHET_RESOLVER'} )
        : ( ( $opts->{'prefer'} eq 'to'   ? ( resolver_class => 'Prophet::Resolver::AlwaysTarget' ) : () ),
            ( $opts->{'prefer'} eq 'from' ? ( resolver_class => 'Prophet::Resolver::AlwaysSource' ) : () )
        )
    );
}

sub fatal_error {
    my $reason = shift;
    die $reason . "\n";

}

1;
