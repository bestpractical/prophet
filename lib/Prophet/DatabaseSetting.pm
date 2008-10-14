package Prophet::DatabaseSetting;
use Moose;
extends 'Prophet::Record';
use Params::Validate;
use JSON;

has default => (
    is => 'ro'
);

has label => (
    isa => 'Maybe[Str]',
    is => 'rw' 
);


sub new { 
        shift->SUPER::new( type => '__prophet_db_settings', @_);
}


sub initialize {
    my $self = shift;
    warn "My default is ".$self->default;
    warn "My uuid is ". $self->uuid;
    $self->set($self->default);
}

sub set {
    my $self = shift;
    my $entry;
    if (exists $_[1]  || !ref($_[0]))  {
        $entry = [@_];
    } else { 
        $entry = shift @_;
    }
       my  $content = to_json($entry, { canonical => 1, pretty=> 0, utf8=>1, allow_nonref => 0}  );
    
    
    if ($self->handle->record_exists( uuid => $self->uuid, type => $self->type)) {
        $self->set_props( props => { content => $content, label => $self->label});
    } else {
        $self->_create_record( props => { content => $content, label => $self->label }, uuid => $self->uuid );
    }
}


sub get {
    my $self = shift;
    my $entry = from_json($self->prop('content') , { utf8 => 1 });
    return $entry;
    # XXX TODO do we really want to just get the first one?

}
1;


