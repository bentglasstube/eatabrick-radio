#/bin/env perl

use Dancer;
use radio;

radio::read_songs_in_background;
radio::read_news;
radio::start_playback;

dance;
