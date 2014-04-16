package EaBRadio;
use Dancer ':syntax';

use Net::MPD;
use LWP::UserAgent;

use utf8;
use strict;
use warnings;

our $VERSION = '0.1';

# TODO make dynamic
my $HOST = 'alan.radio.eatabrick.org';

# cache mpd connection
my $mpd = undef;
sub mpd {
  unless ($mpd) {
    debug "Opening new connection to $HOST";
    $mpd = Net::MPD->connect($HOST)
  }

  $mpd->ping;
  $mpd->update_status;
  return $mpd;
}

get '/' => sub {
  template 'index';
};

get '/listen.*' => sub {
  my ($ext) = splat;
  redirect "http://$HOST:8000/radio.$ext";
};

get '/metadata' => sub {
  content_type 'application/json';
  to_json(mpd->current_song);
};

get '/playlist' => sub {
  content_type 'application/json';
  to_json([ mpd->playlist_info ]);
};

get '/art' => sub {
  my $album = param('album');
  my $artist = param('artist');

  unless ($album and $artist) {
    my $info = mpd->current_song;
    $album = $info->{Album};
    $artist = $info->{Artist};
  }

  my $xml = LWP::UserAgent->new->post('http://ws.audioscrobbler.com/2.0', {
      method => 'album.getinfo',
      api_key => '4827e70daf0106ae5a88b268c083e65b',
      artist => $artist,
      album => $album,
    })->decoded_content;

  # TODO real xml parser
  my ($url) = $xml =~ m{<image size="small">(.*?)</image>};
  $url ||= '/unknown.png';

  header 'Cache-Control', 'no-cache, must-revalidate';
  redirect $url;
};

post '/skip' => sub {
  mpd->next;

  content_type 'application/json';
  to_json({ status => 'success' });
};

1;
