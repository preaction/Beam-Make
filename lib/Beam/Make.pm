package Beam::Make;
our $VERSION = '0.001';
# ABSTRACT: Recipes to declare and resolve dependencies between things

=head1 SYNOPSIS

    ### container.yml
    # This stores useful objects for our recipes
    dbh:
        $class: DBI
        $method: connect
        $args:
            - dbi:SQLite:RECENT.db

    # This file contains our recipes
    # Download a list of recent changes to CPAN
    RECENT-6h.json:
        commands:
            - curl -O https://www.cpan.org/RECENT-6h.json
    # Parse that JSON file into a CSV using an external program
    RECENT-6h.csv:
        requires:
            - RECENT-6h.json
        commands:
            - yfrom json RECENT-6h.json | yq '.recent.[]' | yto csv > RECENT-6h.csv
    # Build a SQLite database to hold the recent data
    RECENT.db:
        $class: Beam::Make::DBI::Schema
        dbh: { $ref: 'container.yml:dbh' }
        schema:
            - table: recent
              columns:
                - path: VARCHAR(255)
                - epoch: DOUBLE
                - type: VARCHAR(10)
    # Load the recent data CSV into the SQLite database
    cpan-recent:
        $class: Beam::Make::DBI::CSV
        requires:
            - RECENT.db
            - RECENT-6h.csv
        dbh: { $ref: 'container.yml:dbh' }
        table: recent
        file: RECENT-6h.csv

    ### Load the recent data into our database
    $ beam make cpan-recent

=head1 DESCRIPTION

=head1 SEE ALSO

=cut

use v5.20;
use warnings;
use Log::Any qw( $LOG );
use Moo;
use experimental qw( signatures postderef );
use Time::Piece;
use YAML ();
use Beam::Wire;
use Scalar::Util qw( blessed );
use List::Util qw( max );
use Beam::Make::Cache;
use File::stat;
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
        $LOG->debug( "Want to build: $target" );
        if ( grep { $_ eq $target } @target_stack ) {
            die "Recursion at @target_stack";
        }
        # If we already have the recipe, it must already have been run
        if ( $recipes{ $target } ) {
            $LOG->debug( "Nothing to do: $target already built" );
            return $recipes{ $target }->last_modified;
        }

        # If there is no recipe for the target, it must be a source
        # file. Source files cannot be built, but we do want to know
        # when they were last modified
        if ( !$conf->{ $target } ) {
            $LOG->debug(
                "$target has no recipe and "
                . ( -e $target ? 'exists as a file' : 'does not exist as a file' )
            );
            return stat( $target )->mtime if -e $target;
            die $LOG->errorf( q{No recipe for target "%s" and file does not exist}."\n", $target );
        }

        # Resolve any references in the recipe object via Beam::Wire
        # containers.
        my $target_conf = $self->_resolve_ref( $conf->{ $target } );
        my $class = delete( $target_conf->{ '$class' } ) || 'Beam::Make::File';
        $LOG->debug( "Building recipe object $target ($class)" );
        eval "require $class";
        my $recipe = $recipes{ $target } = $class->new(
            $target_conf->%*,
            name => $target,
            _cache => $cache,
        );

        my $requires_modified = 0;
        if ( my @requires = $recipe->requires->@* ) {
            $LOG->debug( "Checking requirements for $target: @requires" );
            push @target_stack, $target;
            for my $require ( @requires ) {
                $requires_modified = max $requires_modified, __SUB__->( $require );
            }
            pop @target_stack;
        }

        # Do we need to build this recipe?
        if ( $requires_modified > ( $recipe->last_modified || -1 ) ) {
            $LOG->debug( "Building $target" );
            $recipe->make( %vars );
            $LOG->info( "$target updated" );
        }
        else {
            $LOG->info( "$target up-to-date" );
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

