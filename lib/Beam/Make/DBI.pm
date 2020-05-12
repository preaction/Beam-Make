package Beam::Make::DBI;

use v5.20;
use warnings;
use Moo;
use Time::Piece;
use Digest::SHA qw( sha1_base64 );
use List::Util qw( pairs );
use experimental qw( signatures postderef );

extends 'Beam::Make::Recipe';
has dbh => ( is => 'ro', required => 1 );
has query => ( is => 'ro', required => 1 );

sub make( $self, %vars ) {
    my $dbh = $self->dbh;
    for my $sql ( $self->query->@* ) {
        $dbh->do( $sql );
    }
    $self->_cache->set( $self->name, $self->_cache_hash );
    return 0;
}

sub _cache_hash( $self ) {
    # If our write query changed, we should update
    my $content = sha1_base64( join "\0", $self->query->@* );
    return $content;
}

sub last_modified( $self ) {
    my $last_modified = $self->_cache->last_modified( $self->name, $self->_cache_hash );
    return $last_modified;
}

1;

