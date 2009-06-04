package Prophet::ReplicaFeedExporter;
use Any::Moose;
use IO::Handle;
extends 'Prophet::ReplicaExporter';

has output_handle => (
    is => 'rw',
    lazy => 1,
    default => sub {
        my $self = shift;
        if ($self->has_target_path) {
            open(my $outs, ">", $self->target_path) || die $!;
            $outs->autoflush(1);
            return $outs;
        } else {
            return <STDOUT>;
        }

    }

);


my $feed_updated;


sub output {
    my $self = shift;
    my $content = shift;
   $self->output_handle->print( $content);


}

sub export {
    my $self = shift;

    $self->output( $self->feed_header());
    $self->source_replica->resolution_db_handle->traverse_changesets(
        after    => 0,
        callback => sub {
            my %args = shift;
            $self->output( $self->format_resolution_changeset($args{changeset}));
        }
    );
    $self->source_replica->traverse_changesets(
        after    => 0,
        callback => sub {
            my %args = (@_);
            $self->output( $self->format_changeset($args{changeset}));
        }
    );
    $self->output( tag( 'updated', $feed_updated ));
    $self->output( "</feed>");
}

sub feed_header {
    my $self = shift;

    return join(
        "\n", '<?xml version="1.0" encoding="utf-8"?>',
        '<feed xmlns="http://www.w3.org/2005/Atom">',

        tag( 'id' => 'urn:uuid:' . $self->source_replica->uuid ),
        tag( 'title' => 'Prophet feed of ' . $self->source_replica->db_uuid
        ),

        tag( 'prophet:latest-sequence', $self->source_replica->latest_sequence_no )
    );
}

sub format_resolution_changeset {
    my $self = shift;
    my $cs   = shift;

    $feed_updated = $cs->created_as_rfc3339;
    return tag(
        'entry', undef,
        sub {
            my $output =

                tag( author => undef, sub { tag( name => $cs->creator ) } )
                . tag(title => 'Resolution '
                    . $cs->sequence_no . ' by '
                    . ( $cs->creator || 'nobody' ) . ' @ '
                    . $cs->original_source_uuid )
                . tag(
                id => 'prophet:' . $cs->original_sequence_no . '@' . $cs->original_source_uuid )
                . tag( published => $cs->created_as_rfc3339 )
                . tag( updated   => $cs->created_as_rfc3339 )
                . '<content type="text">' . "\n"
                . tag('prophet:resolution')
                . tag( 'prophet:sequence' => $cs->sequence_no )
                . output_changes($cs)
                . "</content>"."\n";
            return $output;

        }
    );
}

sub format_changeset {
    my $self = shift;
    my $cs   = shift;

    $feed_updated = $cs->created_as_rfc3339;
    return tag(
        'entry', undef,
        sub {
            my $output =

                tag( author => undef, sub { tag( name => $cs->creator ) } )
                . tag(title => 'Change '
                    . $cs->sequence_no . ' by '
                    . ( $cs->creator || 'nobody' ) . ' @ '
                    . $cs->original_source_uuid )
                . tag(
                id => 'prophet:' . $cs->original_sequence_no . '@' . $cs->original_source_uuid )
                . tag( published => $cs->created_as_rfc3339 )
                . tag( updated   => $cs->created_as_rfc3339 )
                . '<content type="text">' . "\n"
                . tag( 'prophet:sequence' => $cs->sequence_no )
                . (
                $cs->is_nullification ? tag( 'prophet:nullifcation' => $cs->is_nullification )
                : ''
                )
                . (
                $cs->is_resolution ? tag( 'prophet:resolution' => $cs->is_resolution )
                : ''
                )
                . output_changes($cs)
                . '</content>';
            return $output;

        }
    );
}

sub output_changes {
    my $cs     = shift;
    my $output = '';
    foreach my $change ( $cs->changes ) {
        $output .= tag(
            'prophet:change',
            undef,
            sub {
                my $change_data
                    = tag( 'prophet:type',        $change->record_type )
                    . tag( 'prophet:uuid',        $change->record_uuid )
                    . tag( 'prophet:change-type', $change->change_type )
                    . ( $change->is_resolution ? tag('prophet:resolution') : '' )
                    . (
                    $change->resolution_cas
                    ? tag( 'prophet:resolution-fingerprint', $change->resolution_cas )
                    : ''
                    );

                foreach my $prop_change ( $change->prop_changes ) {
                    $change_data .= tag(
                        'prophet:property',
                        undef,
                        sub {
                            tag( 'prophet:name' => $prop_change->name )
                                . tag( 'prophet:old' => $prop_change->old_value )
                                . tag( 'prophet:new' => $prop_change->new_value );
                        }
                    );

                }
                return $change_data;
            }
        );
        return $output;
    }
    return $output;
}

my $depth = 0;

sub tag ($$;&) {
    my $tag     = shift;
    my $value   = shift;
    my $content = shift;

    my $output;

    $depth++;
    $output .= " " x $depth;
    if ( !$content && !defined $value ) {
        $output .= "<$tag/>\n";
    } else {
        $output .= "<$tag>";
        if ($value) {
            Prophet::Util::escape_utf8( \$value );
            $output .= $value;
        }
        if ($content) {
            $output .= "\n";
            $output .= $content->();
            $output .= " " x $depth;
        }
        $output .= "</$tag>" . "\n";
    }
    $depth--;
    return $output;
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

