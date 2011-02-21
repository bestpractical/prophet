package Prophet::Replica::file;
use Any::Moose;
extends 'Prophet::Replica::prophet';
sub scheme { 'file' }

sub replica_exists {
    my $self = shift;
    return 0 unless defined $self->fs_root && -d $self->fs_root;
    return 0 unless -e Prophet::Util->catfile( $self->fs_root => 'database-uuid' );
    return 1;
}

sub new {
    my $class = shift;
    my %args = @_;
    
    my @probe_types = ($args{app_handle}->default_replica_type, 'file', 'sqlite');

    my %possible;
    for my $type (@probe_types) {
        my $ret;
        eval {
            my $other = "Prophet::Replica::$type";
            Prophet::App->try_to_require($other);
            $ret = $type eq "file" ? $other->SUPER::new(@_) : $other->new(@_);
        };
        next if $@ or not $ret;
        return $ret if $ret->replica_exists;
        $possible{$type} = $ret;
    }
    if (my $default_type =  $possible{$args{app_handle}->default_replica_type} ) { 
        return $default_type;
    } else {
        $class->log_fatal("I don't know what to do with the Prophet replica ".
            "type you specified: ".$args{app_handle}->default_replica_type.
            "\nIs your URL syntax correct?");
    }
}

no Any::Moose;
1;
