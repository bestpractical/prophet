package Prophet::ContentAddressedStore;
use Any::Moose;

use JSON;
use Digest::SHA qw(sha1_hex);

has root => (
    isa => 'Str',
    is  => 'rw',
);

sub write {
    my ($self, $content) = @_;
    $content = $$content if ref($content) eq 'SCALAR';
    $content = to_json( $content,
            { canonical => 1, pretty => 0, utf8 => 1 } )
        if ref($content);
    my $fingerprint      = sha1_hex($content);
    my $content_filename = File::Spec->catfile(
        $self->root => Prophet::Util::hashed_dir_name($fingerprint) );

    Prophet::Util->write_file( file => $content_filename, content => $content);

    return $fingerprint;
}

__PACKAGE__->meta->make_immutable();
no Any::Moose;
1;
