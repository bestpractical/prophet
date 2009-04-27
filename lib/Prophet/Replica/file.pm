package Prophet::Replica::file;
use base 'Prophet::Replica::prophet';
sub scheme { 'file' }

sub replica_exists {
    my $self = shift;
    return -d $self->fs_root ? 1 : 0;
}

sub new {
    my $class = shift;
    my %args = @_;

    my @types = ('file','sqlite');
    unshift @types, $ENV{PROPHET_REPLICA_TYPE} if $ENV{PROPHET_REPLICA_TYPE};

    my @possible;
    for my $type (@types) {
        my $ret = eval {
            my $other = "Prophet::Replica::$type";
            Prophet::App->try_to_require($other);
            $ret = $type eq "file" ? $other->SUPER::new(@_) : $other->new(@_);
        };
        next if $@ or not $ret;
        return $ret if $ret->replica_exists;
        push @possible, $ret;
    }
    return $possible[0];
}

1;
