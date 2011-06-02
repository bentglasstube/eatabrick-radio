package player;

use strict;
use warnings;
use threads;
use threads::shared;

use Dancer ':syntax';
use File::MimeInfo::Magic;
use File::Find;
use MP3::Tag;
use MPEG::Audio::Frame;
use Shout;

our $VERSION = '0.1';

our @songs   :shared = ();
our @queue   :shared = ();
our @command :shared = ();
our $current :shared = undef;

sub get_next_song {
  lock @queue;

  return shift @queue if @queue;
  return undef unless @songs;
  return $songs[$#songs * rand];
}

sub set_song {
  lock $current;
  $current = shift;
}

sub start_playback {
  threads->create('play')->detach;
}

sub read_songs {
  threads->create(sub {
    debug 'Scanning song directory';
  
    lock @songs;
    @songs = ();

    find({
      no_chdir => 1,
      wanted => sub {
        return unless -f $_;
        my $type = mimetype($_);
  
        if ($type and $type eq 'audio/mpeg') {
          push @songs, $_;
        } else {
          $type ||= 'Unknown type';
          debug "Unusable file $_ ($type)";
        }
      },
    }, setting('path_songs'));
  });
}

sub play {
  my %settings = (
    host => 'localhost',
    port => 8000,
    nonblocking => 0,
    dumpfile => undef,
    format => SHOUT_FORMAT_MP3,
    protocol => SHOUT_PROTOCOL_HTTP,
    public => 1,
  );

  my $shout = Shout->new(%settings, %{setting('shout')});

  unless ($shout->open) {
    warning 'Cannot connect to shout server: ' . $shout->get_error;
    return;
  }

  my $buffer = '';

  while (1) { 
    my $song = get_next_song();
    unless ($song) {
      warning 'No song to play';
      last;
    }

    my $file = IO::File->new($song, 'r');
    unless ($file) {
      warning "Unable to open $song: $!";
      next;
    }

    set_song $song;

    my $mp3 = MP3::Tag->new($song);

    $shout->set_metadata(
      title  => $mp3->title,
      artist => $mp3->artist,
      album  => $mp3->album,
    );

    debug "Playing $song";

    while (my $frame = MPEG::Audio::Frame->read($file)) {
      threads->yield;

      lock @command;
      if (my $command = shift @command) {
        if ($command eq 'skip') {
          debug 'Skipping song';
          last;
        } elsif ($command eq 'stop') {
          debug 'Stopping playback thread';

          set_song undef;
          $shout->close;
          return;
        }
      }

      $shout->set_audio_info(
        SHOUT_AI_BITRATE => $frame->bitrate,
        SHOUT_AI_SAMPLERATE => $frame->sample,
      );

      if ($shout->send($frame->asbin)) {
        $shout->sync;
      } else {
        warning 'Sending to shoutcast failed: ' . $shout->get_error;

        set_song undef;
        $shout->close;
        
        return;
      }
    }
  } 
}

sub command {
  lock @command;
  push @command, shift;
}

sub respond {
  my $data = shift;
  content_type 'text/plain';
  return "$data\n";
}

get '/' => sub {
  respond $current;
};

get '/queue' => sub {
  respond join "\n", @queue;
};

post '/queue' => sub {
  lock @queue;
  push @queue, params->{path};
  respond 'ok';
};

post '/skip' => sub {
  command 'skip';
  respond 'ok';
};

post '/start' => sub {
  start_playback;
  respond 'ok';
};

post '/reload' => sub {
  read_songs;
  respond 'ok';
};

# default route (404)
any qr{.*} => sub { 
  status 'not_found'; 
  respond 'not found';
};

true;
