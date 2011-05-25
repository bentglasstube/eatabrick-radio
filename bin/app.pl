#/bin/env perl

use Dancer;
use radio;

radio::read_songs;
radio::read_news;
radio::start_playback;

dance;
