use warnings;
use strict;


package Prophet::Server::ViewHelpers;
use base 'Exporter::Lite';
use Params::Validate qw/validate/;
use Template::Declare::Tags;
use Prophet::Web::Field;
our @EXPORT = qw(page content widget function);

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
                h1 { $title };
                $code->( $self, @args );

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
    my %args = validate(
        @_,
        {   action => { regex => qr/^(?:create|update|delete)$/ },
            record => 1,
            order  => 0,
            name   => {
                regex    => qr/^(?:|[\w\d]+)$/,
                optional => 1
            },
        }
    );

    my %bits = {
        order => $args{order},
        name  => $args{'name'},
        uuid  => $args{'record'}->uuid
    };

    my $string
        = "|"
        . join( "|", map { $args{$_} ? $_ . "-" . $args{$_} : '' } keys %bits )
        . "|";

    input {
        attr {
            type => 'hidden',
            name => "prophet-action|" . $string,

            value => $args{'action'}
        };
    };

}

sub widget {
    my %args = validate( @_, { prop => 1, record => 1 } );

    my $f = Prophet::Web::Field->new(
        name   => Prophet::Server::ViewHelpers->_generate_name(%args),
        record => $args{record},
        label  => $args{prop},
        value  => $args{record}->prop( $args{'prop'} )
    );
    outs_raw($f->render);
}

sub _generate_name {
    my $class = shift;
    my %args = validate( @_, { prop => 1, record => 1 } );
    my $r = $args{'record'};
    return "prophet-field||uuid-".$r->uuid."|prop-".$args{prop}."|";
}

1;
