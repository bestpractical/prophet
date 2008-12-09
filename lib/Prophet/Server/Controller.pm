package Prophet::Server::Controller;
use Moose;
use Prophet::Util;

has cgi => (is => 'rw', isa => 'CGI');
has failed => ( is => 'rw', isa => 'Bool');
has failure_message => ( is => 'rw', isa => 'Str');
has actions => (is => 'rw', isa => 'HashRef');
has app_handle => (is => 'rw', isa => 'Prophet::App');

=head1 NAME

=head1 METHODS

=head1 DESCRIPTION

=cut

=head1 METHODS

=cut


sub extract_actions_from_cgi {
    my $self = shift;

    my $actions = {};
   foreach my $param ($self->cgi->all_parameters){
        next unless $param =~ /^prophet-function-(.*)$/;
        my $name = $1;
        warn "Duplicate action definition for @{[$name]}." if (exists $actions->{$name});


        my $action_data = $self->cgi->param($param);
        my $attr = $self->string_to_hash($action_data);

        $actions->{$name} = $attr;
        $actions->{$name}->{params} = $self->params_for_action_from_cgi($name);
   } 
   $self->actions($actions);
}

sub params_for_action_from_cgi {
    my $self   = shift;
    my $action = shift;

    my $values;
    for my $field ( $self->cgi->all_parameters ) {
        next unless ( $field =~ /^prophet-field-function-$action-prop-(.*)$/ );
        my $name     = $1;
        my $meta     = {};
        $meta->{prop} = $name;
        $meta->{value} = $self->cgi->param($field);
        $meta->{original_value} = $self->cgi->param( "original-value-" . $field );
        $values->{$name} = $meta;

    }

    return $values;
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
        warn "AIEEE: $err";
    }
}

sub canonicalize_actions {
    my $self    = shift;
    my $actions = $self->actions;
    foreach my $action ( keys %$actions ) {
        foreach my $param (
            keys %{ $actions->{$action}->{params} }

            )
        {
            if ( $actions->{$action}->{params}->{$param}->{original_value} eq
                $actions->{$action}->{params}->{$param}->{value} )
            {

                delete $actions->{$action}->{params}->{$param};
                next;
            }

        }

    }

}

sub validate_actions {

}

sub execute_actions {
    my $self = shift;

    foreach my $action (keys %{$self->actions}) {

        if ($self->actions->{$action}->{action} eq 'update') {
            $self->_exec_action_update($self->actions->{$action});
        } elsif ($self->actions->{$action}->{action} eq 'create') {
            $self->_exec_action_create($self->actions->{$action});
        } else {
            die "I don't know how to handle a ".$self->actions->{$action}->{action};
        }

        warn "My action is $action";
        warn YAML::Dump($self->actions->{$action}); use YAML;
    }

}


sub _exec_action_create {
    my $self = shift;
    my $action = shift;

    die $action->{class} ." is not a valid class " unless (UNIVERSAL::isa($action->{class}, 'Prophet::Record'));
    my $object = $action->{class}->new(  app_handle => $self->app_handle);
    my ( $val, $msg ) = $object->create(
        props => {
            map {
                $action->{params}->{$_}->{prop} => $action->{params}->{$_}->{value}
                } keys %{ $action->{params} }
            }

    );
    warn $val, $msg;

}
sub _exec_action_update {
    my $self = shift;
    my $action = shift;

    my $object = Prophet::Util->instantiate_record( uuid => $action->{uuid}, class=>$action->{class}, app_handle=> $self->app_handle);
    warn "My reocrd is $object";
    warn YAML::Dump($action); use YAML;
    my ( $val, $msg ) = $object->set_props(
        props => {
            map {
                $action->{params}->{$_}->{prop} => $action->{params}->{$_}->{value}
                } keys %{ $action->{params} }
            }

    );
    warn "Updated the record" . $val, $msg;

}


sub string_to_hash {
    my $self = shift;
    my $data = shift;
    my @bits = grep {$_} split( /\|/, $data );
    my %attr = map { split( /=/, $_ ) } @bits;
    return \%attr;
}


__PACKAGE__->meta->make_immutable;
no Moose;

1;

