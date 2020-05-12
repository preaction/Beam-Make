package Beam::Make::DBI::CSV;

use v5.20;
use warnings;
use autodie;
use Moo;
use Time::Piece;
use Text::CSV;
use Digest::SHA qw( sha1_base64 );
use experimental qw( signatures postderef );
use Log::Any qw( $LOG );

extends 'Beam::Make::Recipe';
has dbh => ( is => 'ro', required => 1 );
has table => ( is => 'ro', required => 1 );
has file => ( is => 'ro', required => 1 );
has csv => ( is => 'ro', default => sub { Text::CSV->new } );

sub make( $self, %vars ) {
    my $dbh = $self->dbh;
    open my $fh, '<', $self->file;
    my $csv = $self->csv;
    my @fields = $csv->getline( $fh )->@*;
    my $sth = $dbh->prepare(
        sprintf 'INSERT INTO %s ( %s ) VALUES ( %s )',
        $dbh->quote_identifier( $self->table ),
        join( ', ', map { $dbh->quote_identifier( $_ ) } @fields ),
        join( ', ', ('?')x@fields ),
    );
    while ( my $row = $csv->getline( $fh ) ) {
        $sth->execute( @$row );
    }
    $self->_cache->set( $self->name, $self->_cache_hash );
    return 0;
}

sub _cache_hash( $self ) {
    my $content = join ';',
        map { join ',', @$_ }
        $self->dbh->selectall_arrayref( 'SELECT * FROM ' . $self->table )->@*;
    return sha1_base64( $content );
}

sub last_modified( $self ) {
    return $self->_cache->last_modified( $self->name, $self->_cache_hash );
}

1;

