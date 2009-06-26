#!perl -i
use strict;
use warnings;
use Prophet::Test::Editor;

# perl script to trick Proc::InvokeEditor with for the settings command

my %tmpl_files = ( '--first' => 'aliases.tmpl',
);

Prophet::Test::Editor::edit(
    tmpl_files => \%tmpl_files,
    edit_callback => sub {
        my %args = @_;
        my $option = $args{option};

        if ($option eq '--first') {
            s/^pull -l/something different/; # both an add and a delete
            s/(?<=foo = )bar baz/sigh/; # just change a value
        }
        print;
    },
    verify_callback => sub { },
);
