package Prophet::DatabaseSetting;
use Moose;
extends 'Prophet::Record';
use Params::Validate;

sub new { 
        shift->SUPER::new( type => '__prophet_db_settings', @_);
}



sub set {
    my $self = shift;
    # XXX TODO - better serialization of values. json?
    my $values = join(';', @_);
    
    
    if ($self->handle->record_exists( uuid => $self->uuid, type => $self->type)) {
        $self->set_props( props => { content => $values});
    } else {
        $self->_create_record( props => { content => $values }, uuid => $self->uuid );
    }
}


sub get {
    my $self = shift;
    my @entries =  split(/;/, $self->prop('content'));
    return wantarray ? @entries : shift @entries;
    # XXX TODO do we really want to just get the first one?

}
1;


