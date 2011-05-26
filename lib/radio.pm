package radio;

use strict;
use warnings;

use Dancer ':syntax';

use threads;
use threads::shared;

use File::MimeInfo::Magic;
use File::Find;
use File::Temp;
use File::Copy;

use MP3::Tag;
use MPEG::Audio::Frame;

use IO::File;
use IO::String;

use Archive::Zip;

use POSIX qw(ceil);
use Digest::SHA1 'sha1_base64';

use Shout;

our $VERSION = '0.1';

our %songs   :shared = ();
our %albums  :shared = ();
our @news            = ();

our @queue   :shared = ();
our @command :shared = ();
our $current :shared = undef;

our $pb              = ();

MP3::Tag->config(autoinfo => 'ID3v2');

sub urlify {
  my $string = lc shift;
  $string =~ s/[^a-z0-9]+/_/g;
  return $string;
}

sub add_news {
  my $path = shift;

  my $file = IO::File->new($path, 'r');
  my $post = {
    path => $path,
    posted => ($file->stat)[10],
    body => join('', $file->getlines),
  };
  
  @news = sort {$b->{posted} <=> $a->{posted}} @news, $post;
}

sub read_news {
  debug 'Scanning news directory';

  @news = ();

  my $path = setting('path_news');
  add_news $_ for <$path/*.txt>;
}

sub add_song {
  my $path = shift;

  my $mp3 = MP3::Tag->new($path) or return;
  $mp3->get_tags;

  (my $id = sha1_base64($path)) =~ s/\//_/g;

  my $song = shared_clone({
    id => $id,
    path => $path,
    artist => $mp3->artist,
    title => $mp3->title,
    album => $mp3->album,
    track => $mp3->track1 || 0,
  });

  if (my $art = $mp3->select_id3v2_frame_by_descr('APIC')) {
    $art = $art->{_Data} if ref($art) eq 'HASH';
    my $type = mimetype(IO::String->new($art));

    if ($type =~ /^image\//) {
      $song->{art} = shared_clone({
        type => $type,
        data => $art,
      });
    }
  }

  my $album_id = urlify($song->{album});
  my $artist = $mp3->select_id3v2_frame_by_descr('TPE2') || $song->{artist};
  
  $song->{album_uri} = sprintf('/songs/%s', $album_id);
  $song->{uri} = sprintf('/songs/%s/%u', $album_id, $song->{track});

  lock %albums;
  lock %songs;

  $albums{$album_id} ||= shared_clone({
    id => $album_id,
    title => $song->{album},
    artist => $artist,
    songs => shared_clone([]),
    uri => $song->{album_uri},
    art => shared_clone($song->{art}),
  });
  
  if ($albums{$album_id}{songs}[$song->{track}]) {
    warning "Multiple songs for track $song->{track} on album $song->{album}";
  } else {
    $albums{$album_id}{songs}[$song->{track}] = $songs{$id} = $song;
  }
}

sub read_songs {
  debug 'Scanning song directory';

  lock %songs;
  %songs = ();

  lock %albums;
  %albums = ();
  
  find({
    no_chdir => 1,
    wanted => sub {
      return unless -f $_;
      my $type = mimetype($_);

      if ($type and $type eq 'audio/mpeg') {
        add_song($_);
      } else {
        $type ||= 'Unknown type';
        debug "Unusable file $_ ($type)";
      }
    },
  }, setting('path_songs'));
}

sub get_next_song {
  lock @queue;

  return shift @queue if @queue;
  return undef unless %songs;

  my @keys = keys %songs;
  return $songs{$keys[$#keys * rand]};
}

sub set_song {
  lock $current;
  $current = shift;
}

sub play {
  debug 'Starting playback thread';

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

    my $file = IO::File->new($song->{path}, 'r');
    unless ($file) {
      warning "Unable to open $song->{path}: $!";
      next;
    }

    set_song $song;

    $shout->set_metadata(
      title => $song->{title},
      artist => $song->{artist},
      album => $song->{album}
    );

    while (my $frame = MPEG::Audio::Frame->read($file)) {
      threads->yield;

      lock @command;
      if (my $command = shift @command) {
        if ($command eq 'skip') {
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

sub start_playback {
  if ($pb and $pb->is_running) {
    warning 'Playback thread already running with id ' . $pb->tid;
    return;
  } else {
    my $pb = threads->create('play');
  }
}

sub stop_playback {
  if ($pb and $pb->is_running) {
    lock @command;
    push @command, 'stop';
    $pb->join;
  } else {
    warning 'Playback thread not running';
  }
}

sub flash { 
  my $type = @_ > 1 ? shift : '';
  my $message = shift;
  
  session->{flash}{$message} = $type;
}

sub require_login {
  return 1 if session('user');
  
  flash warning => 'You must log in to view this page.';
  session(requested_page => request->path_info);
  
  redirect '/login';

  return 0;
}

sub authenticate {
  my ($name, $pass) = @_;
  
  return $pass eq setting('admin_pass');
}

sub ago {
  my $timestamp = shift;

  return 'Never' unless $timestamp;

  my $now = time;
  my $minutes = int(($now - $timestamp) / 60);

  my $count = 0;
  my $unit = 'minute';

  if ($minutes < 1) {
    return 'Just now';
  } elsif ($minutes < 55) {
    $count = ceil($minutes / 5) * 5;
  } elsif ($minutes < 23 * 60) {
    $count = ceil($minutes / 60);
    $unit = 'hour';
  } elsif ($minutes < 24 * 60 * 6) {
    $count = ceil($minutes / 60 / 24);
    $unit = 'day';
  } elsif ($minutes < 24 * 60 * 7 * 4) {
    $count = ceil($minutes / 60 / 24 / 7);
    $unit = 'week';
  } elsif ($minutes < 24 * 60 * 30 * 18) {
    $count = ceil($minutes / 60 / 24 / 30);
    $unit = 'month';
  } else {
    $count = ceil($minutes / 60 / 24 / 365);
    $unit = 'year';
  }

  return sprintf('%u %s%s ago', $count, $unit, $count == 1 ? '' : 's');
}

sub add_new_song {
  my $path = shift;

  if (my $mp3 = MP3::Tag->new($path)) {
    $mp3->get_tags;

    my $title = $mp3->title or return 'Missing title';
    my $artist = $mp3->select_id3v2_frame_by_descr('TPE2') || $mp3->artist or return 'Missing artist';
    my $album = $mp3->album or return 'Missing album';
    my $track = $mp3->track1 or return 'Missing track';

    my $dir = sprintf('%s/%s - %s', setting('path_songs'), $artist, $album);
    my $file = sprintf('%02u %s.mp3', $track, $title);
    my $new = "$dir/$file";

    return 'File already exists' if -e $new;

    mkdir $dir;
    copy $path, $new or return "Failed to copy file: $!";
    if (my $song = add_song($new)) {
      return $song;
    } else {
      return 'Failed to add song';
    }
  } else {
    return "Could not open $path";
  }
}


before_template sub {
  my $tokens = shift;
  
  $tokens->{current} = $current; 
  $tokens->{ago} = \&ago;
  $tokens->{stream_uri} = setting('stream_uri');
};

get '/' => sub { 
  template 'news', { posts => \@news };
};

post '/' => sub {
  require_login or return;

  (my $id = sha1_base64(time * rand)) =~ s/\//_/g;

  my $path = setting('path_news') . "/$id.txt";
  my $file = IO::File->new($path, 'w');

  if ($file) {
    $file->print(params->{post});
    $file->close();

    add_news($path);
    flash 'News posted';
  } else {
    flash error => "Unable to open news file $path: $!";
  }

  redirect '/';
};

post '/news/delete' => sub {
  require_login or return;

  my @post = grep {$_->{id} eq params->{id}} @news;
  if ($post[0]) {
    if (unlink $post[0]->{path}) {
      flash 'Post deleted';
      @news = grep {$_->{id} ne params->{id}} @news;
    } else {
      flash error => "Could not delete post: $!";
    }

    redirect '/';
  } else {
    status 'not found';
    template '404';
  }
};

get '/songs' => sub {
  if (my $q = params->{q}) {
    template 'songs', { songs => search_songs($q) };
  } else {
    my @albums = map $albums{$_}, sort {
      $albums{$a}{title} cmp $albums{$b}{title}
    } keys %albums;

    template 'albums', { albums => \@albums };
  }
};

get '/songs/:album.png' => sub {
  if (my $album = $albums{params->{album}}) {
    if ($album->{art}) {
      content_type $album->{art}{type};
      return $album->{art}{data};
    } else {
      return send_file 'unknown.png';
    }
  } else {
    status 'not_found';
    template '404';
  }
};

get '/songs/:album' => sub {
  if (my $album = $albums{params->{album}}) {
    template 'tracks', { album => $album };
  } else {
    status 'not_found';
    template '404';
  }
};

post '/songs/:album' => sub {
  if (my $album = $albums{params->{album}}) {
    if (params->{enqueue}) {
      require_login or return;

      lock @queue;
      push @queue, grep { defined $_ } @{$album->{songs}};

      flash 'Album added to queue';
    }

    redirect $album->{uri};
  } else {
    status 'not_found';
    template '404';
  }

};

get '/songs/:album/:n.mp3' => sub {
  require_login or return;

  if (my $song = $albums{params->{album}}{songs}[params->{n}]) {
    content_type 'audio/mpeg';
    my $file = IO::File->new($song->{path}, 'r');
    return join '', $file->getlines();
  } else {
    status 'not_found';
    template '404';
  }
};

get '/songs/:album/:n.png' => sub {
  if (my $song = $albums{params->{album}}{songs}[params->{n}]) {
    if ($song->{art}) {
      content_type $song->{art}{type};
      return $song->{art}{data};
    } else {
      return send_file 'unknown.png';
    }
  } else {
    status 'not_found';
    template '404';
  }
};

get '/songs/:album/:n' => sub {
  if (my $song = $albums{params->{album}}{songs}[params->{n}]) {
    template 'song', { 
      song => $song,
      mp3 => MP3::Tag->new($song->{path}),
    };
  } else {
    status 'not_found';
    template '404';
  }
};

post '/songs/:album/:n' => sub {
  if (my $song = $albums{params->{album}}{songs}[params->{n}]) {
    if (params->{enqueue}) {
      lock @queue;
      push @queue, $song;

      flash 'Song enqueued';
    } elsif (params->{play}) {
      require_login or return;

      lock @queue;
      unshift @queue, $song;

      lock @command;
      push @command, 'skip';

      flash 'Song playing';
    }

    redirect $song->{uri};
  } else {
    status 'not_found';
    template '404';
  }
};

get '/upload' => sub { 
  require_login or return;

  template 'upload';
};

post '/upload' => sub {
  require_login or return;

  my @results = ();

  if (my $file = upload('upload')) {
    my $type = mimetype($file->tempname);
    if ($type eq 'audio/mpeg') {
      my $result = add_new_song($file->tempname);
      if (ref $result) {
        flash 'Song added';
        redirect "/songs/$result->{id}";
        return;
      } else {
        flash warning => $result;
      }
    } elsif ($type eq 'application/zip') {
      if (my $zip = Archive::Zip->new($file->tempname)) {

        for my $member ($zip->members) {
          my $file = IO::String->new($zip->contents($member));
          next unless mimetype($file) eq 'audio/mpeg';

          my $temp = File::Temp->new->filename;
          $zip->extractMemberWithoutPaths($member, $temp);
          my $result = add_new_song($temp);
          if (ref $result) {
            push @results, { filename => $member->fileName, song => $result };
          } else {
            push @results, { filename => $member->fileName, error => $result };
          }
        }

        flash warning => 'No music files in zip' unless @results;
      } else {
        flash error => "Could not process zip archive";
      }
    } else {
      flash warning => "Cannot process $type files";
    }
  } else {
    flash warning => 'Please select a file';
  }

  template 'upload', { results => \@results };
};

get '/queue' => sub {
  template 'queue', { queue => \@queue };
};

post '/queue' => sub {
  require_login or return;

  if (params->{rescan}) {
    read_songs;
    flash 'Music directory rescanned';
  } elsif (params->{skip}) {
    if ($current) {
      lock @command;
      push @command, 'skip';

      flash 'Song skipped';
    } else {
      flash warning => 'Not playing';
    }
  } elsif (params->{start}) {
    if ($current) {
      flash warning => 'Already playing';
    } elsif (%songs) {
      start_playback;
      flash 'Playback started';
    } else {
      flash warning => 'No songs to play';
    }
  } elsif (params->{stop}) {
    if ($current) {
      stop_playback;
      flash 'Playback stopped';
    } else {
      flash warning => 'Not playing';
    }
  } elsif (params->{remove}) {
    my @new = ();
    for (@queue) {
      if ($_->{id} eq params->{id}) {
        flash 'Song removed from queue';
      } else {
        push @new, $_;
      }
    }
  
    lock @queue;
    @queue = @new;
  } elsif (params->{play}) {
    my @new = ();
    for (@queue) {
      if ($_->{id} eq params->{id}) {
        unshift @new, $_;
        flash 'Song moved to top of queue';
      } else {
        push @new, $_;
      }
    }

    lock @queue;
    @queue = @new;
  }

  redirect '/queue';
};

get '/login' => sub { 
  template 'login' 
};

post '/login' => sub {
  if (authenticate(params->{name}, params->{pass})) {
    flash 'Welcome, ' . params->{name} . '.';

    my $uri = session('requested_page') || '/';
    
    session(requested_page => undef);
    session(user => params->{name});
    
    redirect $uri;
  } else {
    flash warning => 'Invalid credentials.';
    redirect '/login';
  }
};

get '/logout' => sub {
  session(user => undef);
  flash 'You have been logged out.';
  redirect '/';
};

# default route (404)
any qr{.*} => sub { 
  status 'not_found'; 
  template '404';
};

true;
