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

    my @types = ('sqlite');
    unshift @types, $ENV{PROPHET_REPLICA_TYPE} if $ENV{PROPHET_REPLICA_TYPE};
    for (@types) {
        my $ret = eval {
            my $other = "Prophet::Replica::$_";
            Prophet::App->require($other);
            $ret = $other->new(@_);
        };
        return $ret if not $@ and $ret and $ret->replica_exists;
    }
    return $class->SUPER::new(@_);
}

1;
