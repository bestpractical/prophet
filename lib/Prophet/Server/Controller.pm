package Prophet::Server::Controller;
use Moose;
use Prophet::Util;
use Prophet::Web::Result;

has cgi => (is => 'rw', isa => 'CGI');
has failure_message => ( is => 'rw', isa => 'Str');
has functions => (is => 'rw', isa => 'HashRef');
has app_handle => (is => 'rw', isa => 'Prophet::App');
has result => ( is => 'ro', isa => 'Prophet::Web::Result');



=head1 NAME

=head1 METHODS

=head1 DESCRIPTION

=cut

=head1 METHODS

=cut

sub extract_functions_from_cgi {
    my $self = shift;

    my $functions = {};
   foreach my $param ($self->cgi->all_parameters){
        next unless $param =~ /^prophet-function-(.*)$/;
        my $name = $1;
        warn "Duplicate function definition for @{[$name]}." if (exists $functions->{$name});


        my $function_data = $self->cgi->param($param);
        my $attr = $self->string_to_hash($function_data);
        $attr->{name} = $name;

        $functions->{$name} = $attr;
        $functions->{$name}->{params} = $self->params_for_function_from_cgi($name);
   } 
   $self->functions($functions);
}

sub params_for_function_from_cgi {
    my $self   = shift;
    my $function = shift;

    my $values;
    for my $field ( $self->cgi->all_parameters ) {
        if ( $field =~ /^prophet-field-function-$function-prop-(.*)$/ ) {
        my $name     = $1;
        $values->{$name} = {
            prop           => $name,
            value          => $self->cgi->param($field),
            original_value => $self->cgi->param( "original-value-" . $field )
        };
    }
    elsif ($field =~ /^prophet-fill-function-$function-prop-(.*)$/) {
        my $name = $1;
        my $meta = {};
        my $value = $self->cgi->param($field);
        next unless ($value =~ /^function-(.*)\|result-(.*)$/);
        $values->{$name} = {
            prop           => $name,
            from_function => $1,
            from_result => $2
        };
    } 
    else {
            next;
    }

    }

    return $values;
}

sub handle_functions {
    my $self = shift;

   my @workflow = qw(
       extract_functions_from_cgi 
       canonicalize_functions
       validate_functions
       execute_functions    
    );
    eval {
        $self->$_() for @workflow;
    }; 
    
    if (my $err = $@) {
        warn "This run failed - $err";
        $self->result->success(0);
        $self->result->message($err);   
    }

}

sub canonicalize_functions {
    my $self    = shift;
    my $functions = $self->functions;
    foreach my $function ( keys %$functions ) {
        foreach my $param ( keys %{ $functions->{$function}->{params} } ) {
            if ( 
                defined $functions->{$function}->{params}->{$param}->{original_value} &&
                ($functions->{$function}->{params}->{$param}->{original_value} eq
                $functions->{$function}->{params}->{$param}->{value} )) {
                delete $functions->{$function}->{params}->{$param};
                next;
            }

        }

    }

}

sub validate_functions {

}


sub fill_params_from_previous_functions {
    my $self = shift;   
    my $function = shift;

    my $params = $self->functions->{$function}->{params};

    foreach my $param ( keys %$params) {
            if ( my $from_function = $params->{$param}->{from_function}) {
                my $from_result = $params->{$param}->{from_result};  
                my $func_result = $self->result->get($from_function);
                # XXX TODO - $from_result should be locked down tighter
                if ($func_result->can($from_result)) { 
                    $params->{$param}->{value} = $func_result->$from_result();
                }

            }

    }

}

sub execute_functions {
    my $self = shift;
    my $fs = $self->functions;

    foreach my $function ( sort { $fs->{$a}->{order} <=> $fs->{$b}->{order}}  keys %{$fs}) {
        $self->fill_params_from_previous_functions($function); 
        if ($fs->{$function}->{action} eq 'update') {
            $self->_exec_function_update($fs->{$function});
        } elsif ($fs->{$function}->{action} eq 'create') {
            $self->_exec_function_create($fs->{$function});
        } else {
            die "I don't know how to handle a ".$fs->{$function}->{action};
        }

    }

}

sub _exec_function_create {
    my $self = shift;
    my $function = shift;

    die $function->{class} ." is not a valid class " unless (UNIVERSAL::isa($function->{class}, 'Prophet::Record'));
    my $object = $function->{class}->new(  app_handle => $self->app_handle);
    my ( $val, $msg ) = $object->create(
        props => {
            map {
                $function->{params}->{$_}->{prop} => $function->{params}->{$_}->{value}
                } keys %{ $function->{params} }
            }

    );

    my $res = Prophet::Web::FunctionResult->new( function_name => $function->{name}, 
                                                 class => $function->{class},
                                                 success => $object->uuid? 1 :0,
                                                 record_uuid => $object->uuid,
                                                 msg => ($msg || 'Record created'));
                                                
    $self->result->set($function->{name} => $res);
}

sub _exec_function_update {
    my $self = shift;
    my $function = shift;

    my $object = Prophet::Util->instantiate_record( uuid => $function->{uuid}, class=>$function->{class}, app_handle=> $self->app_handle);
    my ( $val, $msg ) = $object->set_props(
        props => {
            map {
                $function->{params}->{$_}->{prop} => $function->{params}->{$_}->{value}
                } keys %{ $function->{params} }
            }

    );
    my $res = Prophet::Web::FunctionResult->new( function_name => $function->{name}, 
                                                 class => $function->{class},
                                                 success => $val? 1 :0,
                                                 record_uuid => $object->uuid,
                                                 msg => ($msg || 'Record updated'));
                                                
    $self->result->set($function->{name} => $res);

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

