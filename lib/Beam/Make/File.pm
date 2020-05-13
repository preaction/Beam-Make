package Beam::Make::File;
our $VERSION = '0.002';
# ABSTRACT: A Beam::Make recipe to build a file from shell scripts

=head1 SYNOPSIS

    ### Beamfile
    a.out:
        requires:
            - main.c
        commands:
            - cc -Wall main.c

=head1 DESCRIPTION

This L<Beam::Make> recipe class creates a file by running one or more
shell scripts. The recipe's name should be the file that will be created
by the recipe.

=head1 SEE ALSO

L<Beam::Make>, L<Beam::Wire>, L<DBI>

=cut

use v5.20;
use warnings;
use Moo;
use File::stat;
use Time::Piece;
use Digest::SHA;
use experimental qw( signatures postderef );

extends 'Beam::Make::Recipe';

=attr commands

An array of commands to run. Commands can be strings, which will be interpreted by
the shell, or arrays, which will be invoked directly by the system.

    # Interpreted as a shell script. Pipes, environment variables, redirects,
    # etc... allowed
    - cc -Wall main.c

    # `cc` invoked directly. Shell functions will not work.
    - [ cc, -Wall, main.c ]

    # A single, multi-line shell script
    - |
        if [ $( date ) -gt $DATE ]; then
            echo Another day $( date ) >> /var/log/calendar.log
        fi

=cut

has commands => ( is => 'ro', required => 1 );

sub make( $self, %vars ) {
    for my $cmd ( $self->commands->@* ) {
        my @cmd = ref $cmd eq 'ARRAY' ? @$cmd : ( $cmd );
        system @cmd;
        if ( $? != 0 ) {
            die sprintf 'Error running external command "%s": %s', "@cmd", $?;
        }
    }
    # XXX: If the recipe does not create the file, throw an error
    $self->cache->set( $self->name, $self->_cache_hash );
    return 0;
}

sub _cache_hash( $self ) {
    return -e $self->name ? Digest::SHA->new( 1 )->addfile( $self->name )->b64digest : '';
}

sub last_modified( $self ) {
    return -e $self->name ? $self->cache->last_modified( $self->name, $self->_cache_hash ) : 0;
}

1;

