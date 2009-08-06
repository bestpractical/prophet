package Prophet::Test::Participant;
use Any::Moose;
use Prophet::Test;
use Test::Exception;

has name => (
    is  => 'rw',
    isa => 'Str',
);

has arena => (
    is       => 'rw',
    isa      => 'Prophet::Test::Arena',
    weak_ref => 1,
);

sub BUILD {
    my $self = shift;
    as_user( $self->name, sub { call_func( [qw(init)] ) } );
    as_user( $self->name, sub { call_func_ok( [qw(search --type Bug --regex .)] ) } );

}

use List::Util qw(shuffle);

my @CHICKEN_DO
    = qw(create_record create_record delete_record  update_record update_record update_record update_record update_record sync_from_peer sync_from_peer noop);

sub take_one_step {
    my $self   = shift;
    my $action = shift || ( shuffle(@CHICKEN_DO) )[0];
    my $args   = shift;
    @_ = ( $self, $args );
    goto $self->can($action);
}

sub _random_props {
    my @prop_values = qw(A B C D E);
    my @prop_keys   = qw(1 2 3 4 5);

    return ( map { "--" . $prop_keys[$_] => $prop_values[$_] } ( 0 .. 4 ) );

}

sub _permute_props {
    my %props = (@_);
    @props{ keys %props } = shuffle( values %props );

    for ( keys %props ) {
        if ( int( rand(10) < 2 ) ) {
            delete $props{$_};
        }
    }

    if ( int( rand(10) < 3 ) ) {
        $props{int(rand(5))+1 } = chr(rand(5)+65);
    }

    return %props;
}

sub noop {
    my $self = shift;
    ok( 1, $self->name . ' - NOOP' );
}

sub delete_record {
    my $self = shift;
    my $args = shift;
    $args->{record} ||= get_random_local_record();

    return undef unless ( $args->{record} );
    $self->record_action( 'delete_record', $args );
    call_func_ok( [ qw(delete --type Scratch --uuid), $args->{record} ] );

}

sub create_record {
    my $self = shift;
    my $args = shift;
    @{ $args->{props} } = _random_props() unless $args->{props};

    my ( $ret, $out, $err ) = call_func_ok( [ qw(create --type Scratch --), @{ $args->{props} } ] );

    #    ok($ret, $self->name . " created a record");
    if ( $out =~ /Created\s+(.*?)\s+(\d+)\s+\((.*)\)/i ) {
        $args->{result} = $3;
    }
    $self->record_action( 'create_record', $args );
}

sub update_record {
    my $self = shift;
    my $args = shift;

    $args->{record} ||= get_random_local_record();
    return undef unless ( $args->{'record'} );

    my ( $ok, $stdout, $stderr ) = call_func( [ qw(show --type Scratch --uuid), $args->{record} ] );

    my %props = map { split( /: /, $_, 2 ) } split( /\n/, $stdout );
    delete $props{id};

    %{ $args->{props} } = _permute_props(%props) unless $args->{props};
    %props = %{ $args->{props} };

    call_func_ok( [ qw(update --type Scratch --uuid), $args->{record}, '--', map { '--' . $_ => $props{$_} } keys %props ],
        $self->name . " updated a record" );

    $self->record_action( 'update_record', $args );

}

sub sync_from_peer {
    my $self = shift;
    my $args = shift;

    my $from = $args->{from} ||= ( shuffle( grep { $_->name ne $self->name } $self->arena->chickens ) )[0]->name;

    $self->record_action( 'sync_from_peer', $args );

    @_ = (
        [ 'merge', '--prefer', 'to', '--from', repo_uri_for($from), '--to', repo_uri_for( $self->name ), '--force' ],
        $self->name . " sync from " . $from . " ran ok!"
    );
    goto \&call_func_ok;

}

sub get_random_local_record {
    my ( $ok, $stdout, $stderr ) = call_func( [qw(search --type Scratch --regex .)] );
    my $update_record = ( shuffle( map { $_ =~ /'uuid': '(\S*?)'/ } split( /\n/, $stdout ) ) )[0];
    return $update_record;
}

sub dump_state {
    my $self = shift;
    my $cli  = Prophet::CLI->new();

    my $state;

    my $records  = Prophet::Collection->new( handle => $cli->handle, type => 'Scratch' );
    my $merges = Prophet::Collection->new( handle => $cli->handle, type => $Prophet::Replica::MERGETICKET_METATYPE );
    my $resolutions = Prophet::Collection->new( handle => $cli->app_handle->handle->resolution_db_handle, type => '_prophet_resolution' );

    $records->matching( sub       {1} );
    $resolutions->matching( sub {1} );
    $merges->matching( sub      {1} );

    %{ $state->{records} }       = map { $_->uuid => $_->get_props } $records->items;
    %{ $state->{merges} }      = map { $_->uuid => $_->get_props } $merges->items;
    %{ $state->{resolutions} } = map { $_->uuid => $_->get_props } $resolutions->items;

    return $state;

}

sub dump_history { }

sub record_action {
    my ( $self, $action, @arg ) = @_;
    $self->arena->record( $self->name, $action, @arg );
}

use Test::Exception;

sub call_func_ok {
    my @args = @_;
    my @ret;
    lives_and {
        @ret = call_func(@args);
        diag("As ".$ENV{'PROPHET_EMAIL'}. " ".join(' ',@{$args[0]}));
        ok( 1, join( " ", $ENV{'PROPHET_EMAIL'}, @{ $args[0] } ) );
    };
    return @ret;
}

sub call_func {
    Carp::cluck unless ref $_[0];

    my @args = @{ shift @_ };
    my $cli = Prophet::CLI->new();

    my $str = '';
    open my $str_fh, '>', \$str;

    my $old_fh = select($str_fh);

    my $ret;
    if (my $p = SVN::Pool->can('new_default')) {
        $p->('SVN::Pool');    
    };

    $ret = $cli->run_one_command(@args);
    select($old_fh) if defined $old_fh;

    return ( $ret, $str, undef );
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;
