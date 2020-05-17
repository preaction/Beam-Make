package Beam::Make::Docker::Image::Hub;
our $VERSION = '0.004';
# ABSTRACT: A Beam::Make recipe to pull/update a Docker image from hub.docker.com

=head1 SYNOPSIS

    ### Beamfile
    nordaaker/convos:
        $class: Beam::Make::Docker::Image::Hub
        image: nordaaker/convos

=head1 DESCRIPTION

This L<Beam::Make> recipe class will update a Docker image by checking
Docker Hub for changes.

This class inherits all attributes from L<Beam::Make::Docker::Image>.

=head1 SEE ALSO

L<Beam::Make::Docker::Image>, L<Beam::Make::Docker::Container>, L<Beam::Make>, L<https://docker.com>

=cut

use v5.20;
use warnings;
use autodie qw( :all );
use Moo;
use Log::Any qw( $LOG );
use JSON::PP qw( decode_json );
use HTTP::Tiny;
use Digest::SHA qw( sha1_base64 );
use experimental qw( signatures postderef );

extends 'Beam::Make::Docker::Image';

sub _cache_hash( $self ) {
    # Check the Docker Hub API to get the image's ID
    my ( $repo, $tag ) = split /:/, $self->image;
    $tag //= 'latest';
    my $token_uri = "https://auth.docker.io/token";
    my $token_data = {
        service => 'registry.docker.io',
        scope => sprintf( 'repository:%s:pull', $repo ),
    };
    my $http = HTTP::Tiny->new;
    $token_uri .= '?' . $http->www_form_urlencode( $token_data );
    my $res = $http->get( $token_uri );
    die "Could not get token: $res->{content}" unless $res->{success};
    my $token = decode_json( $res->{content} )->{token};
    my $manifest_uri = sprintf 'https://registry-1.docker.io/v2/%s/manifests/%s',
        $repo, $tag;
    my %headers = (
        Authorization => "Bearer $token",
        Accept => "application/vnd.docker.distribution.manifest.v2+json",
    );
    $res = $http->get( $manifest_uri, { headers => \%headers } );
    die "Could not get manifest: $res->{content}" unless $res->{success};
    my $manifest = decode_json( $res->{content} );
    return sha1_base64( $manifest->{config}{digest} . $self->_config_hash );
}

1;

