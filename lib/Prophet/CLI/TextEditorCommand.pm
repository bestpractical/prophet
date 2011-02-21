package Prophet::CLI::TextEditorCommand;
use Any::Moose 'Role';
use Params::Validate qw/validate/;

requires 'process_template';

=head2 separator_pattern

A pattern that will match on lines that count as section separators
in record templates. Separator string text is remembered as C<$1>.

=cut

use constant separator_pattern => qr/^=== (.*) ===$/;

=head2 comment_pattern

A pattern that will match on lines that count as comments in
record templates.

=cut

use constant comment_pattern => qr/^\s*#/;

=head2 build_separator $text

Takes a string and returns it in separator form. A separator is a
line of text that denotes a section in a template.

=cut

sub build_separator {
    my $self = shift;
    my $text = shift;

    return "=== $text ===";
}

=head2 build_template_section header => '=== foo ===' [, data => 'bar']

Takes a header text string and (optionally) a data string and formats
them into a template section.

=cut

sub build_template_section {
    my $self = shift;
    my %args = validate (@_, { header => 1, data => 0 });
    return $self->build_separator($args{'header'}) ."\n\n". ( $args{data} || '');
}

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
given in the C<error> arg. If an errors section already exists in the
template, it is replaced with an errors section containing the new errors.

If the template you are editing is not section-based, you can override what
will be prepended to the template by passing in the C<errors_pattern>
argument, and passing in C<old_errors> if a template errors out repeatedly
and there are old errors in the template that need to be replaced.

Other arguments are: C<rtype>: the type of the record being edited. All
arguments except overrides (C<errors_pattern> and C<old_errors> are
required.

=cut

sub handle_template_errors {
    my $self = shift;
    my %args = validate( @_, { error => 1, template_ref => 1,
                               bad_template => 1, rtype => 1,
                               errors_pattern => 0, old_errors => 0 } );
    my $errors_pattern = defined $args{errors_pattern}
                       ? $args{errors_pattern}
                       : "=== errors in this $args{rtype} ===";

    $self->prompt_Yn("Whoops, an error occurred processing your $args{rtype}.\nTry editing again? (Errors will be shown.)") || die "Aborted.\n";

    # template is section-based
    if ( !defined $args{old_errors} ) {
        # if the bad template already has an errors section in it, remove it
        $args{bad_template} =~ s/$errors_pattern.*?\n(?==== .*? ===\n)//s;
    }
    # template is not section-based: we allow passing in the old error to kill
    else {
        $args{bad_template} =~ s/\Q$args{old_errors}\E\n\n\n//;
    }

    ${ $args{'template_ref'} }
        = ($errors_pattern ? "$errors_pattern\n\n" : '')
        . $args{error} . "\n\n\n"
        . $args{bad_template};
    return 0;
}

=head1 calling code must implement

run
process_template

=cut

no Any::Moose 'Role';
1;
