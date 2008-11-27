package Prophet::Server::Controller;
use Moose;


has cgi => (isa => 'CGI');

has failed => ( isa => 'Bool');
has failure_message => ( isa => 'Bool');

=head1 NAME

=head1 METHODS

=head1 DESCRIPTION

=cut

=head1 METHODS

=cut

sub extract_actions_from_cgi {
    my $self = shift;

    my $cgi = $self->cgi;
    my @params = $cgi->all_parameters;

    my $bundles = $self->_bundle_params_by_action(\@params);   
    for (values %$bundles) {
        push  @action_hashes, $self->_bundle_to_hash($_);
    } 
   return \@action_hashes; 
}


sub _bundle_params_by_action {
    my $self = shift;
    my $params = shift;

    my $bundles = {};
    my @actions = $self->_find_actions_from_cgi_params($params);
    foreach my $param (@$params) {
        my $action = $self->_parse_cgi_param_name($param);
    
        $bundles{$action} 
    }
    

    return $bundles;
}

sub find_actions_from_cgi {
    my $self = shift;
    my $params = shift;

    my $cgi = $self->cgi;
    my $actions = {};
   foreach my $param (@$params) {
        next unless $param =~ /^prophet-action(.*)$/;
        my %attr = map {split(/=/) grep {$_} split(/|/,$1)};
        $attr{value} = $cgi->param($param);

        warn "Duplicate action definition for @{[$attr{name}]}." if ($actions{$attr{name}};
        $actions{$attr{name}} = \%attr;
        $actions{$attr{name}}->{params} = 
            $self->params_for_action_from_cgi($attr{name});
   } 

}

sub params_for_action_from_cgi {
    my $self = shift;
    my $action = shift;

    my @params = grep { /^prophet-field|.*?|action=$action|/} 
    $self->cgi->all_parameters
}


sub _parse_cgi_param_name {
    my $self = shift;
    my $param = shift;

    my ($uuid, $prop, $value);
    if ($param =~ /|uuid-(.*?)|) {
        $uuid = $1;
    }
    if ($param =~ /|prop-(.*?)|) {
        $prop = $1;
    }
    my $value = $self->cgi->param($param); 

}

sub _bundle_to_hash {
    my $self = shift;
}

sub handle_actions {
    my $self = shift;

   my @workflow = qw(
       extract_actions_from_cgi 
       canonicalize_actions
       validate_actions
       execute_actions    
    );
    eval {
        $self->$_() for @workflow;
    }; 
    
    if (my $err = $@) {
        $self->failed(1);
        $self->failure_message($err);   
    }
}


sub extract_actions_from_cgi {
    my $self = shift;
}

sub canonicalize_actions {
    my $self = shift;
}

sub validate_actions {

}

sub execute_actions {

}
__PACKAGE__->meta->make_immutable;
no Moose;

1;

