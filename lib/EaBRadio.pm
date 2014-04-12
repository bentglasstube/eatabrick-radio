package EaBRadio;
use Dancer ':syntax';

use Net::MPD;

use utf8;
use strict;
use warnings;

our $VERSION = '0.1';

# TODO make dynamic
my $HOST = 'alan.radio.eatabrick.org';

# TODO cache connection
sub mpd { return Net::MPD->connect($HOST) }

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

post '/skip' => sub {
  mpd->next;

  content_type 'application/json';
  to_json({ status => 'success' });
};

1;
