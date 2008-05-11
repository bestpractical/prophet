use warnings;
use strict;

package Prophet::CLI;
use base qw/Class::Accessor/;
__PACKAGE__->mk_accessors(
    qw/app_class record_class type uuid app_handle primary_commands/);

use Prophet;
use Prophet::Record;
use Prophet::Collection;
use Prophet::Replica;

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);
    $self->record_class('Prophet::Record') unless $self->record_class;

    $self->app_class || $self->app_class('Prophet::App');
    $self->app_class->require();    # unless exists $INC{$app_class_path};
    $self->app_handle( $self->app_class->new );
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


sub _get_cmd_obj {
    my $self = shift;

    my @commands = map { exists $CMD_MAP{$_} ? $CMD_MAP{$_} : $_ } @{ $self->primary_commands };



    my @possible_classes;
    
    my @to_try = @commands;

    while( @to_try ) {
        my $cmd = $self->app_class . "::CLI::Command::" . join( '::', map {ucfirst lc $_} @to_try ) ;    # App::SD::CLI::Command::Ticket::Comment::List
        push @possible_classes, $cmd;
        shift @to_try; # throw away that top-level "Ticket" option 
    }

   my @extreme_fallback_commands = (     $self->app_class . "::CLI::Command::" . ucfirst(lc( $commands[-1] )),    # App::SD::CLI::Command::List
        "Prophet::CLI::Command::" . ucfirst( lc $commands[-1] ),    # Prophet::CLI::Command::List
        $self->app_class . "::CLI::Command::NotFound",
        "Prophet::CLI::Command::NotFound"
    );

    my $class;

    for my $try (@possible_classes, @extreme_fallback_commands) {
        $class = $self->_try_to_load_cmd_class($try);
        last if $class;
    }

    die "I don't know how to parse '" . join(" ", @{$self->primary_commands}) ."'. Are you sure that's a valid command?" unless ($class);

    my $command_obj = $class->new(
        {   cli      => $self,
            commands => $self->primary_commands,
            type     => $self->type,
            uuid     => $self->uuid
        }
    );
    return $command_obj;
}

sub _try_to_load_cmd_class {
    my $self = shift;
    my $class = shift;
    Prophet::App->require_module($class);
    return $class if ( $class->isa('Prophet::CLI::Command') );

    return undef;
}

=head2 parse_args

This routine pulls arguments passed on the command line out of ARGV and sticks them in L</args>. The keys have leading "--" stripped.


=cut

sub parse_args {
    my $self = shift;

    my @primary;
    push @primary, shift @ARGV while ( $ARGV[0] &&  $ARGV[0] =~ /^\w+$/ && $ARGV[0] !~ /^--/ );


    $self->primary_commands( \@primary );

    while (my $name = shift @ARGV) { 
        die "$name doesn't look like --prop-name" if ( $name !~ /^--/ );
        my $val;

        ($name,$val)= split(/=/,$name,2) if ($name =~/=/);
        $name =~ s/^--//;
        $self->{'args'}->{$name} =  ($val || shift @ARGV);
    }

}

=head2 set_type_and_uuid

When working with individual records, it is often the case that we'll be expecting a --type argument and then a mess of other key-value pairs. 

=cut

sub set_type_and_uuid {
    my $self = shift;

    if ( my $uuid = delete $self->{args}->{uuid} ) {
        $self->uuid($uuid);
    }
    if ( $self->{args}->{type} ) {
        $self->type( delete $self->{args}->{'type'} );
    } elsif($self->primary_commands->[-2]) {
        $self->type($self->primary_commands->[-2]); 
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

sub run_one_command {
    my $self = shift;
    $self->parse_args();
    $self->set_type_and_uuid();
    if ( my $cmd_obj = $self->_get_cmd_obj() ) {
        $cmd_obj->run();
    }
}

=head2 edit_text [text] -> text

Filters the given text through the user's C<$EDITOR> using
L<Proc::InvokeEditor>.

=cut

sub edit_text {
    my $self = shift;
    my $text = shift;

    require Proc::InvokeEditor;
    return scalar Proc::InvokeEditor->edit($text);
}

=head2 edit_hash hashref -> hashref

Filters the hash through the user's C<$EDITOR> using L<Proc::InvokeEditor>.

No validation is done on the input or output.

=cut

sub edit_hash {
    my $self = shift;
    my $hash = shift;

    my $input = join "\n", map { "$_: $hash->{$_}\n" } keys %$hash;
    my $output = $self->edit_text($input);

    my $filtered;
    while ($output =~ m{^(\S+?):(.*)$}g) {
        $filtered->{$1} = $2;
    }

    return $filtered;
}

package Prophet::CLI::Command;

use base qw/Class::Accessor/;

__PACKAGE__->mk_accessors(qw/cli record_class command type uuid/);

# XXX type, uuid are only for record commands

sub fatal_error {
    my $self   = shift;
    my $reason = shift;
    die $reason . "\n";

}

sub _get_record {
    my $self = shift;
     my $args = { handle => $self->cli->app_handle->handle, type => $self->type };
    if (my $class =  $self->record_class ) {
        Prophet::App->require_module($class);
        return $class->new( $args);
    } elsif ( $self->type ) {
        return $self->_type_to_record_class( $self->type )->new($args);
    } else { Carp::confess("I was asked to get a record object, but I have neither a type nor a record class")}

}

sub _type_to_record_class {
    my $self = shift;
    my $type = shift;
    my $try = $self->cli->app_class . "::Model::" . ucfirst( lc($type) );
    Prophet::App->require_module($try);    # don't care about fails
    return $try if ( $try->isa('Prophet::Record') );

    $try = $self->cli->app_class . "::Record";
    Prophet::App->require_module($try);    # don't care about fails
    return $try if ( $try->isa('Prophet::Record') );
    return 'Prophet::Record';
}

sub args {
    shift->cli->args(@_);
}

sub app_handle {
    shift->cli->app_handle;
}

package Prophet::CLI::Command::Create;
use base qw/Prophet::CLI::Command/;

sub run {
    my $self   = shift;
    my $record = $self->_get_record;

    $record->create( props => $self->args );
    if (!$record->uuid) {
        warn "Failed to create " . $record->record_type . "\n";
        return;
    }

    print "Created " . $record->record_type . " " . $record->uuid . "\n";

}

package Prophet::CLI::Command::Search;
use base qw/Prophet::CLI::Command/;


sub get_collection_object {
    my $self = shift;

    my $class = $self->_get_record->collection_class;
    Prophet::App->require_module($class);
    my $records = $class->new(
        handle => $self->app_handle->handle,
        type   => $self->type
    );

    return $records;
}

sub get_search_callback {
    my $self = shift;

    if ( my $regex = $self->args->{regex} ) {
            return sub {
                my $item  = shift;
                my $props = $item->get_props;
                map { return 1 if $props->{$_} =~ $regex } keys %$props;
                return 0;
            }
    } else {
        return sub {1}
    }
}
sub run {
    my $self = shift;

    my $records = $self->get_collection_object();
    my $search_cb = $self->get_search_callback();
    $records->matching($search_cb);

    for ( sort { $a->uuid cmp $b->uuid } @{ $records->as_array_ref } ) {
        if ( $_->summary_props ) {
            print $_->format_summary . "\n";
        } else {
            # XXX OLD HACK TO MAKE TESTS PASS
            printf( "%s %s %s \n", $_->uuid, $_->prop('summary') || "(no summary)", $_->prop('status')  || '(no status)' );
        }
    }
}

package Prophet::CLI::Command::Update;
use base qw/Prophet::CLI::Command/;

sub run {
    my $self = shift;

    my $record = $self->_get_record;
    $record->load( uuid => $self->uuid );
    my $result = $record->set_props( props => $self->args );
    if ($result) {
        print $record->type . " " . $record->uuid . " updated.\n";

    } else {
        print "SOMETHING BAD HAPPENED "
            . $record->type . " "
            . $record->uuid
            . " not updated.\n";

    }
}

package Prophet::CLI::Command::Delete;
use base qw/Prophet::CLI::Command/;

sub run {
    my $self = shift;

    my $record = $self->_get_record;
    $record->load( uuid => $self->uuid )
        || $self->fatal_error("I couldn't find that record");
    if ( $record->delete ) {
        print $record->type . " " . $record->uuid . " deleted.\n";
    } else {
        print $record->type . " " . $record->uuid . "could not be deleted.\n";
    }

}

package Prophet::CLI::Command::Show;
use base qw/Prophet::CLI::Command/;

sub run {
    my $self = shift;

    my $record = $self->_get_record;
    if ( !$record->load( uuid => $self->uuid ) ) {
        print "Record not found\n";
        return;
    }

    print "id: " . $record->uuid . "\n";
    my $props = $record->get_props();
    for ( keys %$props ) {
        print $_. ": " . $props->{$_} . "\n";
    }

}

package Prophet::CLI::Command::Merge;
use base qw/Prophet::CLI::Command/;

sub run {

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
        $self->fatal_error(
                  "You appear to be trying to merge two identical replicas. "
                . "Either you're trying to merge a replica to itself or "
                . "someone did a bad job cloning your database" );
    }

    my $opts = $self->args();

    $opts->{'prefer'} ||= 'none';

    if ( !$target->can_write_changesets ) {
        $self->fatal_error( $target->url
                . " does not accept changesets. Perhaps it's unwritable or something"
        );
    }

    $target->import_changesets(
        from  => $source,
        resdb => $self->app_handle->resdb_handle,
        $ENV{'PROPHET_RESOLVER'}
        ? ( resolver_class => 'Prophet::Resolver::' . $ENV{'PROPHET_RESOLVER'} )
        : ( (   $opts->{'prefer'} eq 'to'
                ? ( resolver_class => 'Prophet::Resolver::AlwaysTarget' )
                : ()
            ),
            (   $opts->{'prefer'} eq 'from'
                ? ( resolver_class => 'Prophet::Resolver::AlwaysSource' )
                : ()
            )
        )
    );
}

package Prophet::CLI::Command::Push;
use base qw/Prophet::CLI::Command::Merge/;

sub run {
    my $self = shift;

    my $source_me    = $self->app_handle->handle;
    my $other        = shift @ARGV;
    my $source_other = Prophet::Replica->new( { url => $other } );
    my $resdb        = $source_me->import_resolutions_from_remote_replica(
        from => $source_other );

    $self->_do_merge( $source_me, $source_other );
}

package Prophet::CLI::Command::Export;
use base qw/Prophet::CLI::Command/;

sub run {
    my $self = shift;

    $self->app_handle->handle->export_to( path => $self->args->{path} );
}

package Prophet::CLI::Command::Pull;
use base qw/Prophet::CLI::Command::Merge/;

sub run {

    my $self         = shift;
    my $other        = shift @ARGV;
    my $source_other = Prophet::Replica->new( { url => $other } );
    $self->app_handle->handle->import_resolutions_from_remote_replica(
        from => $source_other );

    $self->_do_merge( $source_other, $self->app_handle->handle );

}

package Prophet::CLI::Command::Server;
use base qw/Prophet::CLI::Command/;

sub run {

    my $self = shift;

    my $opts = $self->args();
    require Prophet::Server::REST;
    my $server = Prophet::Server::REST->new( $opts->{'port'} || 8080 );
    $server->prophet_handle( $self->app_handle->handle );
    $server->run;
}

package Prophet::CLI::Command::NotFound;
use base qw/Prophet::CLI::Command/;

sub run {
    my $self = shift;
    $self->fatal_error( "The command you ran, '"
            . ($self->command || '')
            . "', could not be found. Perhaps running '$0 help' would help?" );
}

1;
