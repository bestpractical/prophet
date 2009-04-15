package Prophet::ContentAddressedStore;
use Any::Moose;

use JSON;
use Digest::SHA qw(sha1_hex);

has fs_root => (
    is  => 'rw',
);

has root => (
    isa => 'Str',
    is  => 'rw',
);

sub write {
    my ($self, $content) = @_;

    $content = $$content
        if ref($content) eq 'SCALAR';

    $content = to_json( $content,
                        { canonical => 1, pretty => 0, utf8 => 1 } )
        if ref($content);
    my $fingerprint = sha1_hex($content);
    Prophet::Util->write_file( file => $self->filename($fingerprint, 1),
                               content => $content );

    return $fingerprint;
}

sub filename {
    my ($self, $key, $full) = @_;
    File::Spec->catfile( $full ? $self->fs_root : (),
                         $self->root =>
                         Prophet::Util::hashed_dir_name($key) );
}

__PACKAGE__->meta->make_immutable();
no Any::Moose;
1;
