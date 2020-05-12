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
use Beam::Wire;
use Scalar::Util qw( blessed );
use Beam::Make::Cache;
with 'Beam::Runnable';

has conf => ( is => 'ro', default => sub { YAML::LoadFile( 'Beamfile' ) } );
# Beam::Wire container objects
has _wire => ( is => 'ro', default => sub { {} } );

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
    my $cache = Beam::Make::Cache->new;

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
        if ( !$conf->{ $target } ) {
            return stat( $target )->mtime if -e $target;
            die sprintf q{No recipe for target "%s" and file does not exist}."\n", $target;
        }

        # Resolve any references in the recipe object via Beam::Wire
        # containers.
        my $target_conf = $self->_resolve_ref( $conf->{ $target } );
        my $class = delete( $target_conf->{ '$class' } ) || 'Beam::Make::File';
        eval "require $class";

        my $recipe = $recipes{ $target } = $class->new(
            $target_conf->%*,
            name => $target,
            _cache => $cache,
        );
        my $last_modified = $recipe->last_modified;
        # We must update no matter what if we can't determine our last
        # modified time
        my $needs_update = $last_modified <= 0;
        if ( my @requires = $recipe->requires->@* ) {
            push @target_stack, $target;
            for my $require ( @requires ) {
                my $require_modified = __SUB__->( $require );
                # If our requirement updated since we last updated, we
                # need to update ourselves
                $needs_update ||= $last_modified < $require_modified;
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

# Resolve any references via Beam::Wire container lookups
sub _resolve_ref( $self, $conf ) {
    return $conf if !ref $conf || blessed $conf;
    if ( ref $conf eq 'HASH' ) {
        if ( grep { $_ !~ /^\$/ } keys %$conf ) {
            my %resolved;
            for my $key ( keys %$conf ) {
                $resolved{ $key } = $self->_resolve_ref( $conf->{ $key } );
            }
            return \%resolved;
        }
        else {
            # All keys begin with '$', so this must be a reference
            # XXX: We should add the 'file:path' syntax to
            # Beam::Wire directly. We could even call it as a class
            # method! We should also move BEAM_PATH resolution to
            # Beam::Wire directly...
            my ( $file, $service ) = split /:/, $conf->{ '$ref' }, 2;
            my $wire = $self->_wire->{ $file };
            if ( !$wire ) {
                for my $path ( split /:/, $ENV{BEAM_PATH} ) {
                    next unless -e join '/', $path, $file;
                    $wire = $self->_wire->{ $file } = Beam::Wire->new( file => join '/', $path, $file );
                }
            }
            return $wire->get( $service );
        }
    }
    elsif ( ref $conf eq 'ARRAY' ) {
        my @resolved;
        for my $i ( 0..$#$conf ) {
            $resolved[$i] = $self->_resolve_ref( $conf->[$i] );
        }
        return \@resolved;
    }
}

1;

