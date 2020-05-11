package Beam::Make::Recipe;

use v5.20;
use warnings;
use Moo;
use Time::Piece;
use experimental qw( signatures postderef );

has name => ( is => 'ro', required => 1 );
has requires => ( is => 'ro', default => sub { [] } );

1;
