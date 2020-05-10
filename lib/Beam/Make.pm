package Beam::Make;
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
use Time::Piece;
use YAML ();
with 'Beam::Runnable';

has conf => ( is => 'ro', default => sub { YAML::LoadFile( 'Beamfile' ) } );

sub run( $self, @argv ) {
    my ( @targets, %vars );

    for my $arg ( @argv ) {
        if ( $arg =~ /^([^=]+)=([^=]+)$/ ) {
            $vars{ $1 } = $2;
        }
        else {
            push @targets, $arg;
        }
    }

    local @ENV{ keys %vars } = values %vars;
    my $conf = $self->conf;

    # Targets must be built in order
    # Prereqs satisfied by original target remain satisfied
    my %recipes; # Built recipes
    my @target_stack;
    # Build a target (if necessary) and return its last modified date.
    # Each dependent will be checked against their depencencies' last
    # modified date to see if they need to be updated
    my $build = sub( $target ) {
        if ( grep { $_ eq $target } @target_stack ) {
            die "Recursion at @target_stack";
        }
        # If we already have the recipe, it must already have been run
        if ( $recipes{ $target } ) {
            return $recipes{ $target }->last_modified;
        }

        # If there is no recipe for the target, it must be a source
        # file. Source files cannot be built, but we do want to know
        # when they were last modified
        return stat( $target )->mtime if !$conf->{ $target };

        require Beam::Make::File;
        my $recipe = $recipes{ $target } = Beam::Make::File->new(
            $conf->{ $target }->%*,
            name => $target,
        );
        my $needs_update = !$recipe->is_fresh( 0 );
        if ( my @requires = $recipe->requires->@* ) {
            push @target_stack, $target;
            for my $require ( @requires ) {
                my $last_modified = __SUB__->( $require );
                $needs_update ||= !$recipe->is_fresh( $last_modified );
            }
            pop @target_stack;
        }
        if ( $needs_update ) {
            say "$target updated";
            $recipe->make( %vars );
        }
        else {
            say "$target up-to-date";
        }
        return $recipe->last_modified;
    };
    $build->( $_ ) for @targets;
}

1;

