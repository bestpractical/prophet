package Prophet::DatabaseSetting;
use Any::Moose;
extends 'Prophet::Record';

use Params::Validate;
use JSON;

has default => (
    is => 'ro',
);

has label => (
    isa => 'Str|Undef',
    is  => 'rw',
);

has '+type' => ( default => '__prophet_db_settings' );

sub BUILD {
    my $self = shift;

    $self->initialize
        unless ($self->handle->record_exists(uuid => $self->uuid, type => $self->type) );
}

sub initialize {
    my $self = shift;

    $self->set($self->default);
}

sub set {
    my $self = shift;
    my $entry;

    if (exists $_[1] || !ref($_[0]))  {
        $entry = [@_];
    } else {
        $entry = shift @_;
    }

    my $content = to_json($entry, {
        canonical    => 1,
        pretty       => 0,
        utf8         => 1,
        allow_nonref => 0,
    });

    my %props = (
        content => $content,
        label   => $self->label,
    );

    if ($self->handle->record_exists( uuid => $self->uuid, type => $self->type)) {
        $self->set_props(props => \%props);
    }
    else {
        $self->_create_record(
            uuid  => $self->uuid,
            props => \%props,
        );
    }
}

sub get_raw {
    my $self = shift;
    my $content = $self->prop('content');
    return $content;
}

sub get {
    my $self = shift;

    $self->initialize() unless $self->load(uuid => $self->uuid);
    my $content = $self->get_raw;

    my $entry = from_json($content, { utf8 => 1 });
    return $entry;
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

