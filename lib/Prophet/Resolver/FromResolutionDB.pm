package Prophet::Resolver::FromResolutionDB;
use Any::Moose;
use Prophet::Change;
use Prophet::Collection;
use JSON;
use Digest::SHA 'sha1_hex';
extends 'Prophet::Resolver';

sub run {
    my $self               = shift;
    my $conflicting_change = shift;
    my $conflict           = shift;
    my $resdb              = shift;    # XXX: we want diffrent collection actually now

    require Prophet::Collection;

    my $res = Prophet::Collection->new(
        handle => $resdb,
        # XXX TODO PULL THIS TYPE FROM A CONSTANT
        type   => '_prophet_resolution-' . $conflicting_change->fingerprint
    );
    $res->matching( sub {1} );
    return unless $res->count;

    my %answer_map;
    my %answer_count;

    for my $answer ($res->items) {
        my $key = sha1_hex( to_json($answer->get_props, {utf8 => 1, pretty => 1, canonical => 1}));
        $answer_map{$key} ||= $answer;
        $answer_count{$key}++;
    }
    my $best = ( sort { $answer_count{$b} <=> $answer_count{$a} } keys %answer_map )[0];

    my $answer = $answer_map{$best};

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

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;
