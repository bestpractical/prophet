package Prophet::CLI::TextEditorCommand;
use Moose::Role;
use Params::Validate qw/validate/;

requires 'process_template';

=head2 try_to_edit template => \$tmpl [, record => $record ]

Edits the given template if possible. Passes the updated
template in to process_template (errors in the updated template
must be handled there, not here).

=cut

sub try_to_edit {
    my $self = shift;
    my %args = validate( @_,
        {   template => 1,
            record   => 0,
        }
    );

    my $template = ${ $args{template} };

    # do the edit
    my $updated = $self->edit_text($template);

    die "Aborted.\n" if $updated eq $template;    # user didn't change anything

    $self->process_template(
        template => $args{template},
        edited   => $updated,
        record   => $args{record}
    );
}

=head2 handle_template_errors error => 'foo', template_ref => \$tmpl_str, bad_template => 'bar', rtype => 'ticket'

Should be called in C<process_template> if errors (usually validation ones)
occur while processing a record template. This method prompts the user to
re-edit and updates the template given by C<template_ref> to contain the bad
template (given by the arg C<bad_template> prefixed with the error messages
given in the C<error> arg.

Other arguments are: C<rtype>: the type of the record being edited. All
arguments are required.

=cut

sub handle_template_errors {
    my $self = shift;
    my %args = validate( @_, { error => 1, template_ref => 1,
                               bad_template => 1, rtype => 1 } );

    $self->prompt_Yn("Whoops, an error occurred processing your $args{rtype}.\nTry editing again? (Errors will be shown.)") || die "Aborted.\n";

    ${ $args{'template_ref'} }
        = "=== Errors in this $args{rtype} ====\n\n"
        . $args{error} . "\n"
        . $args{bad_template};
    return 0;
}

=head1 calling code must implement

run
process_template

=cut

no Moose::Role;
1;
