package Radio::QueueManager;

use strict;
use warnings;

use Dancer ':syntax';
use Dancer::Plugin::MPD;
use Radio::Station;

our $station = Radio::Station->promote(mpd);

sub manage {
  while (1) {
    my $status = $station->status or last;
    my $keep = setting('queue_keep') || 1;
    $station->playlist->delete(0) while $station->current->pos > $keep;

    my $min = setting('queue_size') || 5;
    while ($min > $station->playlist->as_items) {
      my $song = $station->random_song;
      $station->enqueue($song);
      debug "Added $song->{title} to queue";
    }

    sleep 1;
  }

  warning 'Queue manager exited';
}

