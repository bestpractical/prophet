package Prophet::Replica::file;
use base 'Prophet::Replica::prophet';
sub scheme { 'file' }

sub new {
    my $class = shift;
    my %args = @_;

    for (qw/sqlite prophet/) {
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
