use warnings;
use strict;

package Prophet::Resolver::FromResolutionDB;
use base qw/Prophet::Resolver/;
use Prophet::Change;

sub run {
    my $self = shift;
    my $conflicting_change = shift;
    my $conflict = shift;
    my $resdb = shift; # XXX: we want diffrent collection actually now

    my $res = Prophet::Collection->new( handle => $resdb->handle,
                                        type => '_prophet_resolution-'.$conflicting_change->cas_key );
    $res->matching(sub { 1 } );
    my $answer = $res->as_array_ref->[0];
#    for my $answer (@{$res->as_array_ref}) {
        
#    }
    
    warn $answer;
    my $resolution = Prophet::Change->new_from_conflict($conflicting_change);
    for my $prop_conflict ( @{ $conflicting_change->prop_conflicts } ) {
        $resolution->add_prop_change(
            name => $prop_conflict->name,
            old  => $prop_conflict->source_old_value,
            new  => $answer->prop( $prop_conflict->name ),
        );
    }
    return $resolution;

}

1;
