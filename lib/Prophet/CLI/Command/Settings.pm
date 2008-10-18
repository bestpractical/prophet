package Prophet::CLI::Command::Settings;
use Moose;
use Params::Validate qw/validate/;
use JSON;

extends 'Prophet::CLI::Command';
with 'Prophet::CLI::TextEditorCommand';


# use an editor to edit if no props are specified on the commandline,
# allowing the creation of a new comment in the process
sub run {
    my $self = shift;
    my $template_to_edit = $self->make_template;

    my $done = 0;

    while (!$done) {
      $done =  $self->try_to_edit( template => \$template_to_edit);
    }

};

sub make_template {
    my $self = shift;

    my $content = '';
    # get all settings records
    my $settings = $self->app_handle->database_settings;
    for my $name ( keys %$settings ) {
        my @metadata = @{$settings->{$name}};
        my $s = $self->app_handle->setting(  label => $name, uuid => (shift @metadata), default => [@metadata]);
    
        $content .= $self->_make_template_entry($s). "\n\n" ; 
    
    }

    return $content;
}

sub _make_template_entry {
    my $self = shift;
    my $setting = shift;
    # format each settings record as 
    #
    #  # uuid: uuid
    #  key: value, value, value
    #

    return "# uuid: ".$setting->uuid."\n".$setting->label.": ".
        to_json($setting->get, { canonical => 1, pretty=> 0, utf8=>1, allow_nonref => 0}  );
    
    

}


sub parse_template {
    my $self = shift;
    my $template = shift;

    my $uuid = 'NONE';
    my %content;
    my %parsed;
    for my $line ( split(/\n/,$template)) { 
        if ($line =~ /^\s*\#\s*uuid\:\s*(.*?)\s*$/) {
            $uuid = $1;
        } else {
            push @{$content{$uuid}} , $line;
        }

    }

    for my $uuid ( keys %content ) {
        my $data = join("\n",@{$content{$uuid}});
        if ($data =~ /^(.*?)\s*:\s*(.*)\s*$/ms) {
            my $label = $1;
            my $content = $2;
            $parsed{$uuid} = [$label, $content];
        }
    }

    return \%parsed;
}


sub process_template {
    my $self = shift;
    my %args = validate( @_, { template => 1, edited => 1, record => 0} );

    my $updated     = $args{edited};
    my ( $config ) = $self->parse_template($updated);

    no warnings 'uninitialized';
    my $settings = $self->app_handle->database_settings;
    
    for my $uuid ( keys %$config ) {
        my $s = $self->app_handle->setting(   uuid => $uuid);
        my $old_value = $s->get_raw; 
        my $new_value = $config->{$uuid}->[1];
        chomp $new_value;
        if ($old_value ne $new_value) {
            $s->set( from_json($new_value , { utf8 => 1 }));
            print "Changed ".$config->{$uuid}->[0]." from $old_value to $new_value\n"; 
        }


    }
    return 1;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
