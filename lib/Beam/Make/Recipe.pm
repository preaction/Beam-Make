package Beam::Make::Recipe;
our $VERSION = '0.002';
# ABSTRACT: The base class for Beam::Make recipes

=head1 SYNOPSIS

    package My::Recipe;
    use v5.20;
    use Moo;
    use experimental qw( signatures );
    extends 'Beam::Make::Recipe';

    # Make the recipe
    sub make( $self ) {
        ...;
    }

    # Return a Time::Piece object for when this recipe was last
    # performed, or 0 if it can't be determined.
    sub last_modified( $self ) {
        ...;
    }

=head1 DESCRIPTION

This is the base L<Beam::Make> recipe class. Extend this to build your
own recipe components.

=head1 REQUIRED METHODS

=head2 make

This method performs the work of the recipe. There is no return value.

=head2 last_modified

This method returns a L<Time::Piece> object for when this recipe was last
performed, or C<0> otherwise. This method could use the L</cache> object
to read a cached date. See L<Beam::Make::Cache> for more information.

=head1 SEE ALSO

L<Beam::Make>

=cut

use v5.20;
use warnings;
use Moo;
use Time::Piece;
use experimental qw( signatures postderef );

=attr name

The name of the recipe. This is the key in the C<Beamfile> used to refer
to this recipe.

=cut

has name => ( is => 'ro', required => 1 );

=attr requires

An array of recipe names that this recipe depends on.

=cut

has requires => ( is => 'ro', default => sub { [] } );

=attr cache

A L<Beam::Make::Cache> object. This is used to store content hashes and
modified dates for later use.

=cut

has cache => ( is => 'ro', required => 1 );

1;
