package Beam::Make::Docker::Image;
our $VERSION = '0.003';
# ABSTRACT: A Beam::Make recipe to build/pull/update a Docker image

=head1 SYNOPSIS

    ### Beamfile
    nordaaker/convos:
        $class: Beam::Make::Docker::Image

=head1 DESCRIPTION

This L<Beam::Make> recipe class updates a Docker image, either by building it
or by checking a remote repository.

B<NOTE:> This works for basic use-cases, but could use some
improvements. Improvements should attempt to match the C<docker-compose>
file syntax when possible.

=head1 SEE ALSO

L<Beam::Make::Docker::Container>, L<Beam::Make>, L<https://docker.com>

=cut

use v5.20;
use warnings;
use autodie qw( :all );
use Moo;
use Time::Piece;
use Log::Any qw( $LOG );
use File::Which qw( which );
use JSON::PP qw( decode_json );
use Digest::SHA qw( sha1_base64 );
use experimental qw( signatures postderef );

extends 'Beam::Make::Recipe';

=attr image

The image to build or pull. If building, will tag the resulting image.
Required.

=cut

has image => (
    is => 'ro',
    required => 1,
);

=attr build

The path to the build context. If set, will build an image instead of pulling
from a repository.

=cut

has build => (
    is => 'ro',
);

=attr args

A mapping of build args (C<< --build-arg <KEY>=<VALUE> >>).

=cut

has args => (
    is => 'ro',
    default => sub { {} },
);

=attr tags

A list of additional tags for the image.

=cut

has tags => (
    is => 'ro',
    default => sub { [] },
);

=attr dockerfile

The name of the Dockerfile to use. If unset, Docker uses the default name: C<Dockerfile>.

=cut

has dockerfile => (
    is => 'ro',
);

=attr docker

The path to the Docker executable to use. Defaults to looking up
C<docker> in C<PATH>.

=cut

has docker => (
    is => 'ro',
    default => sub { which 'docker' },
);

sub make( $self, %vars ) {
    my @cmd = ( $self->docker );
    if ( my $context = $self->build ) {
        push @cmd, 'build', '-t', $self->image;
        if ( my @tags = $self->tags->@* ) {
            push @cmd, map {; '-t', $_ } @tags;
        }
        if ( my %args = $self->args->%* ) {
            push @cmd, map {; '--build-arg', join '=', $_, $args{$_} } keys %args;
        }
        if ( my $file = $self->dockerfile ) {
            push @cmd, '-f', $file;
        }
        push @cmd, $context;
    }
    else {
        push @cmd, 'pull', $self->image;
    }
    @cmd = $self->fill_env( @cmd );
    $LOG->debug( 'Running docker command: ', @cmd );
    system @cmd;
    delete $self->{_inspect_output} if exists $self->{_inspect_output};

    # Update the cache
    my $info = $self->_image_info;
    my $created = $info->{Created} =~ s/^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}).*$/$1/r;
    my $iso8601 = '%Y-%m-%dT%H:%M:%S';
    $self->cache->set( $self->name, $self->_cache_hash, Time::Piece->strptime( $created, $iso8601 ) );

    return 0;
}

sub _image_info( $self ) {
    state $json = JSON::PP->new->canonical->utf8;
    my $output = $self->{_inspect_output};
    if ( !$output ) {
        my $cmd = join ' ', $self->docker, qw( image inspect ), $self->image;
        $LOG->debug( 'Running docker command:', $cmd );
        $output = `$cmd`;
        $self->{_inspect_output} = $output;
    }
    my ( $image ) = $json->decode( $output )->@*;
    return $image || {};
}

sub _config_hash( $self ) {
    my @keys = grep !/^_|^name$|^cache$/, keys %$self;
    my $json = JSON::PP->new->canonical->utf8;
    my $hash = sha1_base64( $json->encode( { $self->%{ @keys } } ) );
    return $hash;
}

sub _cache_hash( $self ) {
    my $image = $self->_image_info;
    return '' unless keys %$image;
    return sha1_base64( $image->{Id} . $self->_config_hash );
}

sub last_modified( $self ) {
    return $self->cache->last_modified( $self->name, $self->_cache_hash );
}

1;

