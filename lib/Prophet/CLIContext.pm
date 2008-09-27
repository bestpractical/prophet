package Prophet::CLIContext;
use Moose;
use MooseX::ClassAttribute;
use Params::Validate;

has app_handle => (
    is       => 'rw',
    isa      => 'Prophet::App',
    handles  => [qw/handle resdb_handle config/],
    weak_ref => 1,
    required => 1,
);

has uuid => (
    is            => 'rw',
    isa           => 'Str',
    predicate     => 'has_uuid',
    documentation => "This is the uuid set by the user from the commandline",
);

has type => (
    is            => 'rw',
    isa           => 'Str',
    documentation => "This is the type set by the user from the commandline",
);

has args => (
    metaclass => 'Collection::Hash',
    is        => 'rw',
    isa       => 'HashRef',
    default   => sub { {} },
    provides  => {
        set    => 'set_arg',
        get    => 'arg',
        exists => 'has_arg',
        delete => 'delete_arg',
        keys   => 'arg_names',
        clear  => 'clear_args',
    },
    documentation =>
        "This is a reference to the key-value pairs passed in on the commandline",
);

has props => (
    metaclass => 'Collection::Hash',
    is        => 'rw',
    isa       => 'HashRef',
    default   => sub { {} },
    provides  => {
        set    => 'set_prop',
        get    => 'prop',
        exists => 'has_prop',
        delete => 'delete_prop',
        keys   => 'prop_names',
        clear  => 'clear_props',
    },
);

# clear the prop_set too!
after clear_props => sub { my $self = shift; $self->prop_set( () ); };

has prop_set => (
    metaclass  => 'Collection::Array',
    is         => 'rw',
    isa        => 'ArrayRef',
    default    => sub { [] },
    auto_deref => 1,
    provides   => { push => 'add_to_prop_set', },
);
after add_to_prop_set => sub {
    my $self = shift;
    my $args = shift;
    $self->set_prop( $args->{prop} => $args->{value} );
};

has primary_commands => (
    is            => 'rw',
    isa           => 'ArrayRef',
    documentation => "The commands the user executes from the commandline",
);

has record_class => (
    is  => 'rw',
    isa => 'Prophet::Record',
);

=head2 mutate_attributes ( args => $hashref, props => $hashref, type => 'str' )

A hook for running a second command from within a command without having       
to use the commandline argument parsing.  

If C<type>, C<uuid>, or C<primary_commands> are not passed in, the values
from the previous command run are used.

=cut

sub mutate_attributes {
    my $self = shift;
    my %args = @_;

    $self->clear_args();
    $self->clear_props();

    if ( my $cmd_args = $args{args} ) {
        foreach my $arg ( keys %$cmd_args ) {
            if ( $arg eq 'uuid' ) {
                $self->uuid( $cmd_args->{$arg} );
            }
            $self->set_arg( $arg => $cmd_args->{$arg} );
        }
    }
    if ( my $props = $args{props} ) {
        foreach my $prop (@$props) {
            my $key   = $prop->{prop};
            my $value = $prop->{value};
            $self->set_prop( $key => $value );
        }
    }
    if ( my $type = $args{type} ) {
        $self->type($type);
    }

    if ( my $primary_commands = $args{ $self->primary_commands } ) {
        $self->primary_commands( $primary_commands );
    }
}

=head2 cmp_regex

Returns the regex to use for matching property key/value separators.

=cut

sub cmp_regex { '!=|<>|=~|!~|=|\bne\b' }


=head2 setup_from_args

Sets up this context object's arguments and key/value pairs from an array that looks like an @ARGV.

=cut

sub setup_from_args {
    my $self = shift;
    $self->parse_args(@_);
    $self->set_type_and_uuid();

}




=head2 parse_args @args

This routine pulls arguments (specified by --key=value or --key
value) and properties (specified by --props key=value or -- key=value)
as passed on the command line out of ARGV (or something else emulating
ARGV) and sticks them in L</args> or L</props> and L</prop_set> as
necessary. Argument keys have leading "--" stripped.

If a key is not given a value on the command line, its value is set to undef.

More complicated separators such as =~ (for regexes) are also handled (see
L</cmp_regex> for details).

=cut

sub parse_args {
    my $self = shift; 
    my @args = (@_);
    my @primary;
    push @primary, shift @args while ( $args[0] && $args[0] !~ /^--/ );

    # "ticket show 4" should DWIM and "ticket show --id=4"
    $self->set_arg( id => pop @primary )
        if @primary && $primary[-1] =~ /^(?:\d+|[0-9a-f]{8}\-)/i;

    my $collecting_props = 0;

    $self->primary_commands( \@primary );
    my $cmp_re = $self->cmp_regex;

    while ( my $name = shift @args ) {
        die "$name doesn't look like --argument"
            if !$collecting_props && $name !~ /^--/;

        if ( $name eq '--' || $name eq '--props' ) {
            $collecting_props = 1;
            next;
        }

        my $cmp = '=';
        my $val;

        ( $name, $cmp, $val ) = ( $1, $2, $3 )
            if $name =~ /^(.*?)($cmp_re)(.*)$/;
        $name =~ s/^--//;

        # no value specified, pull it from the next argument, unless the next
        # argument is another option
        if ( !defined($val) ) {
            $val = shift @args
                if @args && $args[0] !~ /^--/;

            no warnings 'uninitialized';

            # but wait! does the value look enough like a comparator? if so,
            # shift off another one (if we can)
            if ($collecting_props) {
                if ( $val =~ /^(?:$cmp_re)$/ && @args && $args[0] !~ /^--/ ) {
                    $cmp = $val;
                    $val = shift @args;
                } else {

                    # perhaps they said "foo =~bar"..
                    $cmp = $1 if $val =~ s/^($cmp_re)//;
                }
            }
        }

        if ($collecting_props) {
            $self->add_to_prop_set(
                {   prop  => $name,
                    cmp   => $cmp,
                    value => $val,
                }
            );
        } else {
            $self->set_arg( $name => $val );
        }
    }
}

=head2 set_type_and_uuid

When working with individual records, it is often the case that we'll be
expecting a --type argument and then a mess of other key-value pairs.

This routine figures out and sets C<type> and C<uuid> from the arguments given
on the command-line, if possible. Being unable to figure out a uuid is fatal.

=cut

sub set_type_and_uuid {
    my $self = shift;

    if ( my $id = $self->delete_arg('id') ) {
        if ( $id =~ /^(\d+)$/ ) {
            $self->set_arg( luid => $id );
        } else {
            $self->set_arg( uuid => $id );
        }
    }

    if ( my $uuid = $self->delete_arg('uuid') ) {
        $self->uuid($uuid);
    } elsif ( my $luid = $self->delete_arg('luid') ) {
        my $uuid = $self->handle->find_uuid_by_luid( luid => $luid );
        die "I have no UUID mapped to the local id '$luid'\n"
            if !defined($uuid);
        $self->uuid($uuid);
    }
    if ( my $type = $self->delete_arg('type') ) {
        $self->type($type);
    } elsif ( $self->primary_commands->[-2] ) {
        $self->type( $self->primary_commands->[-2] );
    }
}

=head2 _get_record_object [{ type => 'type' }]

Tries to determine a record class from either the given type argument or
the current object's C<$type> attribute.

Returns a new instance of the record class on success, or throws a fatal
error with a stack trace on failure.

=cut

sub _get_record_object {
    my $self = shift;
    my %args = validate(@_, {
        type => { default => $self->type },
    });

    my $constructor_args = {
        app_handle => $self->app_handle,
        handle     => $self->handle,
        type       => $args{type},
    };

    if ($args{type}) {
        my $class = $self->_type_to_record_class($args{type});
        return $class->new($constructor_args);
    }
    elsif (my $class = $self->record_class) {
        Prophet::App->require($class);
        return $class->new($constructor_args);
    }
    else {
        Carp::confess("I was asked to get a record object, but I have neither a type nor a record class");
    }
}

=head2 _load_record

Attempts to load the record specified by the C<uuid> attribute.

Returns the loaded record on success, or throws a fatal error if no
record can be found.

=cut

sub _load_record {
    my $self = shift;
    my $record = $self->_get_record_object;
    $record->load( uuid => $self->uuid )
        || $self->fatal_error("I couldn't find the " . $self->type . ' ' . $self->uuid);
    return $record;
}

=head2 _type_to_record_class $type

Takes a type and tries to figure out a record class name from it.
Returns C<'Prophet::Record'> if no better class name is found.

=cut

sub _type_to_record_class {
    my $self = shift;
    my $type = shift;

    my $app = $self->app_handle;
    my $app_class = blessed($app);

    my $try = $app_class . "::Model::" . ucfirst( lc($type) );
    $app->try_to_require($try);    # don't care about fails
    return $try if ( $try->isa('Prophet::Record') );

    $try = $app_class . "::Record";
    $app->try_to_require($try);    # don't care about fails
    return $try if ( $try->isa('Prophet::Record') );

    require Prophet::Record;
    return 'Prophet::Record';
}

sub get_collection_object {
    my $self = shift;
    my %args = validate(@_, {
        type => { default => $self->type },
    });

    my $record_class = $self->_get_record_object(type => $args{type});
    my $class = $record_class->collection_class;
    Prophet::App->require($class);

    my $records = $class->new(
        app_handle => $self->app_handle,
        handle     => $self->handle,
        type       => $args{type} || $self->type,
    );

    return $records;
}

=head2 require_uuid

Checks to make sure the uuid attribute is set. Prints an error and dies
if it is not set.

=cut

sub require_uuid {
    my $self    = shift;

    if (!$self->has_uuid) {
        my $type = $self->type;
        my $name = (split /::/, $self->meta->name)[-1];
        die "This command requires a luid or uuid (use --id to specify).\n";
    }
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
