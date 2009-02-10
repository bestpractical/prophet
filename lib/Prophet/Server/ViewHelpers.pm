package Prophet::Server::ViewHelpers;

use warnings;
use strict;

use base 'Exporter::Lite';
use Params::Validate qw/validate/;
use Template::Declare::Tags;
use Prophet::Web::Field;
our @EXPORT = (qw(form page content widget function param_from_function hidden_param));
use Prophet::Server::ViewHelpers::Widget;
use Prophet::Server::ViewHelpers::Function;
use Prophet::Server::ViewHelpers::ParamFromFunction;
use Prophet::Server::ViewHelpers::HiddenParam;


sub page (&;$) {
    unshift @_, undef if $#_ == 0;
    my ( $meta, $code ) = @_;

    sub {
        my $self  = shift;
        my @args  = @_;
        my $title = $self->default_page_title;
        $title = $meta->( $self, @args ) if $meta;
        html {
            attr { xmlns => 'http://www.w3.org/1999/xhtml' };
            show( 'head' => $title );
            body {
                div { 
                    class is 'page';
                    show('header', $title);
                    div { class is 'body';
                     $code->( $self, @args );
                 }
                 }

            };
            show('footer');
        }

      }
}

sub content (&) {
    my $sub_ref = shift;
    return $sub_ref;
}

sub function {
    my $f = Prophet::Server::ViewHelpers::Function->new(@_);
    $f->render;
    return $f;
}

sub param_from_function {
    my $w = Prophet::Server::ViewHelpers::ParamFromFunction->new(@_);
    $w->render;
    return $w;
}

sub hidden_param {
    my $w = Prophet::Server::ViewHelpers::HiddenParam->new(@_);
    $w->render;
    return $w;
}
sub widget {
    my $w = Prophet::Server::ViewHelpers::Widget->new(@_);
    $w->render;
    return $w;
}

BEGIN {
   no warnings 'redefine'; 
    *old_form = \&form;
    *form = sub (&;$){
    my $code = shift;
        old_form ( sub { attr { method => 'post'};
            $code->(@_);
        }
    )
}};


1;
