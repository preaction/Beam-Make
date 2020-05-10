package Beam::Make::File;

use v5.20;
use warnings;
use Moo;
use File::stat;
use Time::Piece;
use experimental qw( signatures postderef );

#extends 'Beam::Make::Recipe';

has name => ( is => 'ro', required => 1 );
has requires => ( is => 'ro', default => sub { [] } );
has commands => ( is => 'ro', required => 1 );

sub make( $self, %vars ) {
    for my $cmd ( $self->commands->@* ) {
        my @cmd = ref $cmd eq 'ARRAY' ? @$cmd : ( $cmd );
        system @cmd;
        if ( $? != 0 ) {
            die sprintf 'Error running external command "%s": %s', "@cmd", $?;
        }
    }
    return 0;
}

sub last_modified( $self ) {
    return -e $self->name ? stat( $self->name )->mtime : 2**31;
}

sub is_fresh( $self, $from ) {
    return -e $self->name && $self->last_modified >= $from;
}

1;

