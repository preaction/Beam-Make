package Beam::Make::Cache;
our $VERSION = '0.003';
# ABSTRACT: Store information about recipes performed

=head1 SYNOPSIS

    my $cache = Beam::Make::Cache->new;

    # Update the cache and track what the content should be
    $cache->set( 'recipe', 'content hash' );

    # Set the last modified time to a specific time by passing
    # a Time::Piece object
    $cache->set( 'recipe', 'content hash', $timestamp );

    # Get a Time::Piece object if the content hashes match
    # Otherwise returns 0
    my $time = $cache->last_modified( 'recipe', 'content hash' );

=head1 DESCRIPTION

This class provides an API to access timestamps and content hashes to validate
recipes and determine which recipes are out-of-date and should be re-run.

=head2 Limitations

The cache file cannot be accessed by more than one process. This limitation may
be fixed in the future. Other cache modules that use distributed databases may
also be created in the future.

=head1 SEE ALSO

L<Beam::Make>

=cut

use v5.20;
use warnings;
use Moo;
use experimental qw( signatures postderef );
use File::stat;
use Time::Piece;
use Scalar::Util qw( blessed );
use YAML ();

=attr file

The path to a file to use for the cache. Defaults to C<.Beamfile.cache> in
the current directory.

=cut

has file => ( is => 'ro', default => sub { '.Beamfile.cache' } );
has _last_read => ( is => 'rw', default => 0 );
has _cache => ( is => 'rw', default => sub { {} } );

=method set

    $cache->set( $name, $hash, $time );

    # Update modified time to now
    $cache->set( $name, $hash );

Set an entry in the cache. C<$name> is the recipe name. C<$hash> is an identifier
for the content (usually a base64 SHA-1 hash from L<Digest::SHA>). C<$time> is a
L<Time::Piece> object to save as the last modified time. If C<$time> is not provided,
defaults to now.

=cut

sub set( $self, $name, $hash, $time=Time::Piece->new ) {
    my $cache = $self->_fetch_cache;
    $cache->{ $name } = {
        hash => $hash,
        time => blessed $time eq 'Time::Piece' ? $time->epoch : $time,
    };
    $self->_write_cache( $cache );
}

=method last_modified

    my $time = $cache->last_modified( $name, $hash );

Get the last modified timestamp (as a L<Time::Piece> object) for the
given recipe C<$name>. If the C<$hash> does not match what was given to
L</set>, or if the recipe has never been made, returns C<0>.

=cut

sub last_modified( $self, $name, $hash ) {
    my $cache = $self->_fetch_cache;
    return Time::Piece->new( $cache->{ $name }{ time } )
        if $cache->{ $name }
        && $cache->{ $name }{ hash } eq $hash
        ;
    return 0;
}

sub _fetch_cache( $self ) {
    my $last_read = $self->_last_read;
    if ( -e $self->file && ( !$last_read || stat( $self->file )->mtime > $last_read ) ) {
        $self->_last_read( stat( $self->file )->mtime );
        $self->_cache( YAML::LoadFile( $self->file ) );
    }
    return $self->_cache;
}

sub _write_cache( $self, $cache ) {
    my $old_cache = $self->_fetch_cache;
    $cache = { %$old_cache, %$cache };
    YAML::DumpFile( $self->file, $cache );
    $self->_cache( $cache );
    $self->_last_read( stat( $self->file )->mtime );
    return;
}

1;

