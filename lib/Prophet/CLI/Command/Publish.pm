package Prophet::CLI::Command::Publish;
use Any::Moose;
extends 'Prophet::CLI::Command::Export';
with 'Prophet::CLI::PublishCommand';
with 'Prophet::CLI::CollectionCommand';

use File::Path;
use File::Spec;

sub usage_msg {
    my $self = shift;
    my $cmd = $self->cli->get_script_name;

    return <<"END_USAGE";
usage: ${cmd}publish --to <location|name> [--html] [--replica]
END_USAGE
}

sub run {
    my $self = shift;

    $self->print_usage if $self->has_arg('h');

    unless ($self->has_arg('to')) {
        warn "No --to specified!\n";
        $self->print_usage;
    }

    # substitute publish-url config variable for to arg if possible
    my %previous_sources_by_name
        = $self->app_handle->config->sources( variable => 'publish-url' );

    my $to = exists $previous_sources_by_name{$self->arg('to')}
        ? $previous_sources_by_name{$self->arg('to')}
        : $self->arg('to');

    # set the temp directory where we will do all of our work, which will be
    # published via rsync
    $self->set_arg(path => $self->tempdir);

    my $export_html = $self->has_arg('html');
    my $export_replica = $self->has_arg('replica');

    # if the user specifies nothing, then publish the replica
    $export_replica = 1 if !$export_html;

    Prophet::CLI->end_pager();
    # if we have the html argument, populate the tempdir with rendered templates
    if ($export_html) {
        print "Exporting a static HTML version of this replica\n";
        $self->export_html() 
    }
    # otherwise, do the normal prophet export this replica
    if ($export_replica) {
        print "Exporting a clone of this replica\n";
        $self->SUPER::run(@_) 
    } 

    my $from = $self->arg('path');

    print "Publishing the exported clone of the replica to $to with rsync\n";
    $self->publish_dir(
        from => $from,
        to   => $to,
    );

    print "Publication complete.\n";

    # create new config section for where to publish this replica
    # if we're using a url rather than a name
    $self->record_replica_in_config($to, $self->handle->uuid, 'publish-url')
        if $to eq $self->arg('to');
}

sub export_html {
	my $self = shift;
        my $path = $self->arg('path');

        # if they specify both html and replica, then stick rendered templates
        # into a subdirectory. if they specify only html, assume they really
        # want to publish directly into the specified directory
        if ($self->has_arg('replica')){
            $path = File::Spec->catdir($path => 'html');
            mkpath([$path]);
        }

        $self->render_templates_into($path);
    }

# helper methods for rendering templates
sub render_templates_into {
    my $self = shift;
    my $dir  = shift;

    require Prophet::Server;
     my $server_class = ref($self->app_handle) . "::Server";
     if (!$self->app_handle->try_to_require($server_class)) {
         $server_class = "Prophet::Server";
     }
    my $server = $server_class->new();
    $server->app_handle( $self->app_handle );
    $server->setup_template_roots();



    # allow user to specify a specific type to render
    my @types = $self->type || $self->types_to_render;

    for my $type (@types) {
        my $subdir = File::Spec->catdir($dir, $type);
        mkpath([$subdir]);

        my $records = $self->get_collection_object(type => $type);
        $records->matching(sub { 1 });

        open (my $fh, '>',File::Spec->catdir($subdir => 'index.html'));
        print { $fh } $server->render_template('record_table' => $records);
        close $fh;

        for my $record ($records->items) {
            open (my $fh, '>',File::Spec->catdir($subdir => $record->uuid.'.html'));
            print { $fh } $server->render_template('record' => $record);
        }
    }
}

sub should_skip_type {
    my $self = shift;
    my $type = shift;

    # should we skip all _private types?
    return 1 if $type eq $Prophet::Replica::MERGETICKET_METATYPE;

    return 0;
}

sub types_to_render {
    my $self = shift;

    return grep { !$self->should_skip_type($_) }
           @{ $self->handle->list_types };
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

