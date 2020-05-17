package Beam::Make::DBI;
our $VERSION = '0.004';
# ABSTRACT: A Beam::Make recipe for executing SQL queries

=head1 SYNOPSIS

    ### container.yml
    # A Beam::Wire container to configure a database connection to use
    sqlite:
        $class: DBI
        $method: connect
        $args:
            - dbi:SQLite:conversion.db

    ### Beamfile
    convert:
        $class: Beam::Wire::DBI
        dbh: { $ref: 'container.yml:sqlite' }
        query:
            - |
                INSERT INTO accounts ( account_id, address )
                SELECT
                    acct_no,
                    CONCAT( street, "\n", city, " ", state, " ", zip )
                FROM OLD_ACCTS

=head1 DESCRIPTION

This L<Beam::Make> recipe class executes one or more SQL queries against
the given L<DBI> database handle.

=head1 SEE ALSO

L<Beam::Make>, L<Beam::Wire>, L<DBI>

=cut

use v5.20;
use warnings;
use Moo;
use Time::Piece;
use Digest::SHA qw( sha1_base64 );
use List::Util qw( pairs );
use experimental qw( signatures postderef );

extends 'Beam::Make::Recipe';

=attr dbh

Required. The L<DBI> database handle to use. Can be a reference to a service
in a L<Beam::Wire> container using C<< { $ref: "<container>:<service>" } >>.

=cut

has dbh => ( is => 'ro', required => 1 );

=attr query

An array of SQL queries to execute.

=cut

has query => ( is => 'ro', required => 1 );

sub make( $self, %vars ) {
    my $dbh = $self->dbh;
    for my $sql ( $self->query->@* ) {
        $dbh->do( $sql );
    }
    $self->cache->set( $self->name, $self->_cache_hash );
    return 0;
}

sub _cache_hash( $self ) {
    # If our write query changed, we should update
    my $content = sha1_base64( join "\0", $self->query->@* );
    return $content;
}

sub last_modified( $self ) {
    my $last_modified = $self->cache->last_modified( $self->name, $self->_cache_hash );
    return $last_modified;
}

1;

