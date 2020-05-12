package Beam::Make::Cache;
our $VERSION = '0.001';
# ABSTRACT: Write a sentence about what it does

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 SEE ALSO

=cut

use v5.20;
use warnings;
use Moo;
use experimental qw( signatures postderef );
use File::stat;
use Time::Piece;
use Scalar::Util qw( blessed );
use YAML ();

has file => ( is => 'ro', default => sub { '.Beamfile.cache' } );
has _last_read => ( is => 'rw', default => 0 );
has _cache => ( is => 'rw', default => sub { {} } );

sub set( $self, $name, $hash, $time ) {
    my $cache = $self->_fetch_cache;
    $cache->{ $name } = { hash => $hash, time => blessed $time eq 'Time::Piece' ? $time->epoch : $time };
    $self->_write_cache( $cache );
}

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

