use warnings;
use strict;


package Prophet::Test::Participant;
use base qw/Class::Accessor/;
__PACKAGE__->mk_accessors(qw/name arena/);
use Prophet::Test;
use Scalar::Util qw/weaken/;




sub new {

    my $self = shift->SUPER::new(@_);
    $self->_setup();
    weaken($self->{'arena'});
    
    return $self;
}

sub _setup {
    my $self = shift;
    as_user($self->name, sub { call_func_ok( [qw(search --type Bug --regex .)])});


}

use List::Util qw(shuffle);

my @CHICKEN_DO = qw(create_record create_record delete_record  update_record update_record update_record update_record update_record sync_from_peer sync_from_peer noop);

sub take_one_step {
    my $self   = shift;
    my $action = shift || ( shuffle(@CHICKEN_DO) )[0];
    my $args   = shift;
    @_ = ($self, $args);
    goto $self->can($action);
}


sub _random_props {
     my @prop_values = Acme::MetaSyntactic->new->name( batman=>5);
     my @prop_keys = Acme::MetaSyntactic->new->name( lotr=>5);

    return( map { "--".$prop_keys[$_] => $prop_values[$_] } (0..4));
        

        
}

sub _permute_props {
    my %props = (@_);
    @props{keys %props} = shuffle(values %props);

    for(keys %props) {
        if(int(rand(10) < 2)){
            delete $props{$_};
        }
    }
    
    if (int(rand(10) < 3)) {
     $props{Acme::MetaSyntactic->new->name( 'lotr')} = Acme::MetaSyntactic->new->name( 'batman');
    }
    

    return %props;
}

sub noop {
    my $self = shift;
    ok(1, $self->name. ' - NOOP');
}
sub delete_record {
    my $self = shift;
    my $args = shift;
    $args->{record} ||= get_random_local_record();

    return undef unless ($args->{record});
    $self->record_action('delete_record', $args);
    call_func_ok( [qw(delete --type Scratch --uuid),  $args->{record}]);



}
sub create_record {
    my $self = shift;
    my $args = shift;
    @{$args->{props}} = _random_props() unless $args->{props};

    my ($ret, $out, $err) = call_func_ok( [qw(create --type Scratch),   @{$args->{props}} ]);

    ok($ret, $self->name . " created a record");
    if ($out =~ /Created\s+(.*?)\s+(.*)$/i) {
       $args->{result} = $2;
    }
    $self->record_action('create_record', $args);
}

sub update_record {
    my $self = shift;
    my $args = shift;

    $args->{record} ||= get_random_local_record();
    return undef unless($args->{'record'});

    my ($ok, $stdout, $stderr) = call_func_ok([qw(update --type Scratch --uuid), $args->{record}]);
   
    my %props = map { split(/: /,$_,2) } split(/\n/,$stdout);
    delete $props{id};

    %{$args->{props}} =_permute_props(%props) unless $args->{props};
    %props = %{ $args->{props} };

   call_func_ok( [ qw(update --type Scratch --uuid), $args->{record},
            map { '--' . $_ => $props{$_} } keys %props ], $self->name . " updated a record" );

    $self->record_action('update_record', $args);

}
sub sync_from_peer {
    my $self = shift;
    my $args = shift;

    my $from = $args->{from} ||= (shuffle(grep { $_->name ne $self->name} @{$self->arena->chickens}))[0]->name;

    $self->record_action('sync_from_peer', $args);

    @_ = ( 
            ['merge', '--prefer', 'to', '--from', repo_uri_for($from),
                '--to', repo_uri_for($self->name) ], $self->name . " sync from " . $from . " ran ok!" );
    goto \&call_func_ok;

}

sub get_random_local_record {
    my ($ok, $stdout, $stderr) = call_func_ok([qw(search --type Scratch --regex .)]);
    my $update_record = (shuffle( map { $_ =~ /^(\S*)/ } split(/\n/,$stdout)))[0];
    return $update_record;
}


sub dump_state {
    my $self = shift;
    my $cli = Prophet::CLI->new();

    my $state;

    my $nodes = Prophet::Collection->new(handle => $cli->handle, type => 'Scratch');
    my $merges = Prophet::Collection->new(handle => $cli->handle, type => $Prophet::Handle::MERGETICKET_METATYPE);
    my $resolutions = Prophet::Collection->new(handle => $cli->resdb_handle, type => '_prophet_resolution');

    $nodes->matching(sub {1});
    $resolutions->matching(sub {1});
    $merges->matching(sub {1});
    
    %{$state->{nodes}}= map { $_->uuid =>  $_->get_props} @{$nodes->as_array_ref};
    %{$state->{merges}} =map { $_->uuid => $_->get_props} @{ $merges->as_array_ref};
    %{$state->{resolutions}} = map { $_->uuid => $_->get_props} @{$resolutions->as_array_ref};





    return $state;

}



sub dump_history {}

sub record_action {
    my ($self, $action, @arg) = @_;
    $self->arena->record($self->name, $action, @arg);
}

use IO::String;

sub call_func_ok {
    my @args = @{ shift @_ };
    my $cmd  = shift @args;
    local (@ARGV) = (@args);
    my $cli = Prophet::CLI->new();
    $cli->parse_record_cmd_args();

    my $str;
    my $str_fh = IO::String->new($str);

    my $old_fh = select($str_fh);

    my $ret;
    if ( my $sub = $cli->can( 'do_' . $cmd ) ) {
        $ret = $sub->($cli);
    } else {
        die "I don't know how to do the $cmd";
    }
    select($old_fh) if defined $old_fh;
    ok(1, join(" ", $cmd, @ARGV));

    return ( $ret, $str, undef);
}


1;
