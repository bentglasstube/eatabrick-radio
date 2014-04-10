package EaBRadio;
use Dancer ':syntax';

use utf8;
use strict;
use warnings;

our $VERSION = '0.1';

get '/' => sub {
  template 'index';
};

get '/listen.*' => sub {
  my ($ext) = splat;
  redirect "http://radio.eatabrick.org:8000/radio.$ext";
};

1;
