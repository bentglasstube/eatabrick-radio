package EaBRadio;
use Dancer ':syntax';

use Net::MPD;
use LWP::UserAgent;

use utf8;
use strict;
use warnings;

our $VERSION = '0.1';

# cache mpd connection
my $mpd = undef;
sub mpd {
  $mpd //= Net::MPD->connect($ENV{MPD_HOST});
  $mpd->ping;
  $mpd->update_status;
  return $mpd;
}

get '/' => sub {
  template 'index';
};

get '/listen.*' => sub {
  my ($ext) = splat;
  my $host = $ENV{MPD_HOST};
  $host =~ s/^.*?@//;
  $host =~ s/:.*?$//;
  redirect "http://$host:8000/radio.$ext";
};

get '/metadata' => sub {
  content_type 'application/json';
  to_json(mpd->current_song);
};

get '/playlist' => sub {
  content_type 'application/json';
  to_json([ mpd->playlist_info ]);
};

#cache for album art
my %_art = ();

get '/art' => sub {
  my $album = param('album');
  my $artist = param('artist');

  unless ($album and $artist) {
    my $info = mpd->current_song;
    $album = $info->{Album};
    $artist = $info->{Artist};
  }

  unless (exists $_art{$album, $artist}) {
    debug "Searching for art for $album, $artist";

    my $xml = LWP::UserAgent->new->post('http://ws.audioscrobbler.com/2.0', {
        method => 'album.getinfo',
        api_key => '4827e70daf0106ae5a88b268c083e65b',
        artist => $artist,
        album => $album,
      })->decoded_content;

    # TODO real xml parser
    my ($url) = $xml =~ m{<image size="small">(.*?)</image>};
    $url ||= '/unknown.png';

    $_art{$album, $artist} = $url;
  }

  header 'Cache-Control', 'no-cache, must-revalidate';
  redirect $_art{$album, $artist};
};

our $last_skip = 0;
post '/skip' => sub {
  content_type 'application/json';

  if (time - $last_skip < 10) {
    to_json({
        status => 'error',
        message => 'Last skip was too recent, please calm down.'
      });
  } else {
    $last_skip = time;
    mpd->next;
    to_json({ status => 'success' });
  }
};

1;
