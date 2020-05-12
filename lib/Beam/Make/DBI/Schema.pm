package Beam::Make::DBI::Schema;

use v5.20;
use warnings;
use Moo;
use Time::Piece;
use List::Util qw( pairs );
use Digest::SHA qw( sha1_base64 );
use experimental qw( signatures postderef );

extends 'Beam::Make::Recipe';
has dbh => ( is => 'ro', required => 1 );
has schema => ( is => 'ro', required => 1 );

sub make( $self, %vars ) {
    my $dbh = $self->dbh;

    # Now, prepare the changes to be made
    my @changes;
    for my $pair ( pairs $self->schema->@* ) {
        my $table = $pair->key;
        my @columns = $pair->value->@*;
        my $table_info = $dbh->table_info( '', '%', qq{$table} )->fetchrow_arrayref;
        if ( !$table_info ) {
            push @changes, sprintf 'CREATE TABLE %s ( %s )', $dbh->quote_identifier( $table ),
                join ', ', map { join ' ', $dbh->quote_identifier( $_->key ), $_->value } pairs @columns;
        }
        else {
            my $column_info = $dbh->column_info( '', '%', $table, '%' )->fetchall_hashref( 'COLUMN_NAME' );
            # Compare columns and add if needed
            for my $pair ( pairs @columns ) {
                my $column_name = $pair->key;
                my $column_type = $pair->value;
                if ( !$column_info->{ $column_name } ) {
                    push @changes, sprintf 'ALTER TABLE %s ADD COLUMN %s %s',
                        $table, $column_name, $column_type;
                }
            }
        }
    }

    # Now execute the changes
    for my $change ( @changes ) {
        $dbh->do( $change );
    }

    $self->_cache->set( $self->name, $self->_cache_hash );
    return 0;
}

sub _cache_hash( $self ) {
    my $dbh = $self->dbh;
    my %tables;
    for my $table_info ( $dbh->table_info( '', '%', '%' )->fetchall_arrayref( {} )->@* ) {
        my $table_name = $table_info->{TABLE_NAME};
        for my $column_info ( $dbh->column_info( '', '%', $table_name, '%' )->fetchall_arrayref( {} )->@* ) {
            my $column_name = $column_info->{COLUMN_NAME};
            push $tables{ $table_name }->@*, $column_name;
        }
    }
    my $content = join ';',
        map { sprintf '%s=%s', $_, join ',', sort $tables{ $_ }->@* } sort keys %tables;
    return sha1_base64( $content );
}

sub last_modified( $self ) {
    return $self->_cache->last_modified( $self->name, $self->_cache_hash );
}

1;

