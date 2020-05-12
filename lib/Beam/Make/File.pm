package Beam::Make::File;

use v5.20;
use warnings;
use Moo;
use File::stat;
use Time::Piece;
use Digest::SHA;
use experimental qw( signatures postderef );

extends 'Beam::Make::Recipe';
has commands => ( is => 'ro', required => 1 );

sub make( $self, %vars ) {
    for my $cmd ( $self->commands->@* ) {
        my @cmd = ref $cmd eq 'ARRAY' ? @$cmd : ( $cmd );
        system @cmd;
        if ( $? != 0 ) {
            die sprintf 'Error running external command "%s": %s', "@cmd", $?;
        }
    }
    $self->_cache->set( $self->name, $self->_cache_hash );
    return 0;
}

sub _cache_hash( $self ) {
    return -e $self->name ? Digest::SHA->new( 1 )->addfile( $self->name )->b64digest : '';
}

sub last_modified( $self ) {
    return $self->_cache->last_modified( $self->name, $self->_cache_hash );
}

1;

