package Prophet::CLIContext;
use Any::Moose;

has app_handle => (
    is      => 'rw',
    isa     => 'Prophet::App',
    lazy    => 1,
    handles => [qw/handle resdb_handle config/],
    weak_ref => 1,
    default => sub {
        return $_[0]->app_class->new;
    },
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
    is        => 'rw',
    isa       => 'HashRef',
    default   => sub { {} },
    documentation =>
        "This is a reference to the key-value pairs passed in on the commandline",
);

has raw_args => (
    is => 'rw',
    isa => 'ArrayRef',
    default => sub {[]},
);


sub set_arg    { $_[0]->args->{$_[1]} = $_[2] }
sub arg        { $_[0]->args->{$_[1]} }
sub has_arg    { exists $_[0]->args->{$_[1]} }
sub delete_arg { delete $_[0]->args->{$_[1]} }
sub arg_names  { keys %{ $_[0]->args } }
sub clear_args { %{ $_[0]->args } = () }

has props => (
    is        => 'rw',
    isa       => 'HashRef',
    default   => sub { {} },
);

sub set_prop    { $_[0]->props->{$_[1]} = $_[2] }
sub prop        { $_[0]->props->{$_[1]} }
sub has_prop    { exists $_[0]->props->{$_[1]} }
sub delete_prop { delete $_[0]->props->{$_[1]} }
sub prop_names  { keys %{ $_[0]->props } }

sub clear_props {
    %{ $_[0]->props } = ();

    # clear the prop_set too!
    $_[0]->prop_set( () );
}

has prop_set => (
    is         => 'rw',
    isa        => 'ArrayRef',
    default    => sub { [] },
    auto_deref => 1,
);

sub add_to_prop_set {
    my $self = shift;
    my $args = shift;

    push @{ $self->prop_set }, $args;

    $self->set_prop( $args->{prop} => $args->{value} );
}

has primary_commands => (
    is            => 'rw',
    isa           => 'ArrayRef',
    documentation => "The commands the user executes from the commandline",
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
        for my $arg ( keys %$cmd_args ) {
            if ( $arg eq 'uuid' ) {
                $self->uuid( $cmd_args->{$arg} );
            }
            $self->set_arg( $arg => $cmd_args->{$arg} );
        }
    }
    if ( my $props = $args{props} ) {
        for my $prop (@$props) {
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

The regex to use for matching property key/value separators.

=cut

use constant cmp_regex => '!=|<>|=~|!~|=|\bne\b';

=head2 $ID_REGEX

The regex to use for matching the id argument (luid / uuid).

=cut

our $ID_REGEX = qr'(?:\d+|[0-9a-fA-F\-]{32,36}|[A-Za-z0-9\-\_]{22})';

=head2 setup_from_args

Sets up this context object's arguments and key/value pairs from an array that
looks like an @ARGV.

=cut

sub setup_from_args {
    my $self = shift;
    $self->raw_args([@_]);
    $self->parse_args(@_);
    $self->set_type_and_uuid();

}

=head2 parse_args @args

This routine pulls arguments (specified by --key=value or --key
value or -k value) and properties (specified by --props key=value or --
key=value) as passed on the command line out of ARGV (or something else
emulating ARGV) and sticks them in L</args> or L</props> and L</prop_set> as
necessary. Argument keys have leading "--" or "-" stripped.

If a key is not given a value on the command line, its value is set to undef.

More complicated separators such as =~ (for regexes) are also handled (see
L</cmp_regex> for details).

=cut

sub parse_args {
    my $self = shift;
    my @args = (@_);
    my @primary;
    push @primary, shift @args while ( $args[0] && $args[0] !~ /^-/ );

    my $collecting_props = 0;

    $self->primary_commands( \@primary );
    my $cmp_re = $self->cmp_regex;

    while ( my $name = shift @args ) {
        die "$name doesn't look like --argument\n"
            if !$collecting_props && $name !~ /^-/;

        if ( $name eq '--' || $name eq '--props' ) {
            $collecting_props = 1;
            next;
        }

        my $cmp = '=';
        my $val;

        ( $name, $cmp, $val ) = ( $1, $2, $3 )
            if $name =~ /^(.*?)($cmp_re)(.*)$/;
        $name =~ s/^(?:--|-)//;

        # no value specified, pull it from the next argument, unless the next
        # argument is another option
        if ( !defined($val) ) {
            $val = shift @args
                if @args && $args[0] !~ /^-/;

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

    $self->set_uuid;
    $self->set_type;
}

sub set_uuid {
    my $self = shift;

    if ( my $id = $self->delete_arg('id') ) {
        if ( $id =~ /^(\d+)$/ ) {
            $self->set_arg( luid => $id );
        }
        else {
            $self->set_arg( uuid => $id );
        }
    }

    if ( my $uuid = $self->delete_arg('uuid') ) {
        $self->uuid($uuid);
    }
    elsif ( my $luid = $self->delete_arg('luid') ) {
        my $uuid = $self->handle->find_uuid_by_luid( luid => $luid );
        die "I have no UUID mapped to the local id '$luid'\n"
            if !defined($uuid);
        $self->uuid($uuid);
    }
}

sub set_type {
    my $self = shift;

    if ( my $type = $self->delete_arg('type') ) {
        $self->type($type);
    }
    # allowance for things like ticket show 77, where 'ticket' is the type
    elsif ( $self->primary_commands->[-1] &&
        $self->primary_commands->[-1] =~ qr/^$Prophet::CLIContext::ID_REGEX$/i
            && $self->primary_commands->[-3] ) {
        $self->type( $self->primary_commands->[-3] );
    }
    elsif ( $self->primary_commands->[-2] ) {
        $self->type( $self->primary_commands->[-2] );
    }
}

sub set_id_from_primary_commands {
    my $self = shift;
    
    if ( (my $id = pop @{$self->primary_commands}) =~ $ID_REGEX ) {
        $self->set_id($id);
    }

}
sub set_id {
    my $self = shift;
    my $id = shift;
    $self->set_arg( id => $id );
    $self->set_uuid;
}



__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;
