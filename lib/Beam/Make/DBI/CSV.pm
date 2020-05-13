package Beam::Make::DBI::CSV;
our $VERSION = '0.001';
# ABSTRACT: A Beam::Make recipe 

=head1 SYNOPSIS

    ### container.yml
    # A Beam::Wire container to configure a database connection to use
    sqlite:
        $class: DBI
        $method: connect
        $args:
            - dbi:SQLite:conversion.db

    ### Beamfile
    load_data:
        $class: Beam::Wire::DBI
        dbh: { $ref: 'container.yml:sqlite' }
        table: cpan_recent
        file: cpan_recent.csv

=head1 DESCRIPTION

This L<Beam::Make> recipe class loads data into a database from a CSV file.

=head1 SEE ALSO

L<Beam::Make>, L<Beam::Wire>, L<DBI>

=cut

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

=attr dbh

Required. The L<DBI> database handle to use. Can be a reference to a service
in a L<Beam::Wire> container using C<< { $ref: "<container>:<service>" } >>.

=cut

has dbh => ( is => 'ro', required => 1 );

=attr table

Required. The table to load data to.

=cut

has table => ( is => 'ro', required => 1 );

=attr file

Required. The path to the CSV file to load.

=cut

has file => ( is => 'ro', required => 1 );

=attr csv

The configured L<Text::CSV> object to use. Can be a reference to a service
in a L<Beam::Wire> container using C<< { $ref: "<container>:<service>" } >>.
Defaults to a new, blank C<Text::CSV> object.

    ### container.yml
    # Configure a CSV parser for pipe-separated values
    psv:
        $class: Text::CSV
        $args:
            - binary: 1
              sep_char: '|'
              quote_char: ~
              escape_char: ~

    ### Beamfile
    # Load a PSV into the database
    load_psv:
        $class: Beam::Make::DBI::CSV
        dbh: { $ref: 'container.yml:sqlite' }
        csv: { $ref: 'container.yml:psv' }
        file: accounts.psv
        table: accounts

=cut

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
    $self->cache->set( $self->name, $self->_cache_hash );
    return 0;
}

sub _cache_hash( $self ) {
    my $content = join ';',
        map { join ',', @$_ }
        $self->dbh->selectall_arrayref( 'SELECT * FROM ' . $self->table )->@*;
    return sha1_base64( $content );
}

sub last_modified( $self ) {
    return $self->cache->last_modified( $self->name, $self->_cache_hash );
}

1;

