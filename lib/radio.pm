package radio;

use strict;
use warnings;

use Dancer ':syntax';

use threads;
use threads::shared;

use File::MimeInfo::Magic;
use File::Find;
use File::Temp;
use MP3::Tag;
use MPEG::Audio::Frame;
use IO::File;
use IO::String;
use Archive::Zip;
use Shout;
use POSIX qw(ceil);
use Digest::SHA1 'sha1_base64';

our $VERSION = '0.1';

our %songs   :shared = ();
our @queue   :shared = ();
our @news    :shared = ();
our $current :shared = undef;
our @command :shared = ();

my $pidfile = IO::File->new(setting('pidfile'), 'w') or die $!;
print $pidfile $$;
close $pidfile;

sub add_news {
  my $path = shift;

  lock @news;

  my $file = IO::File->new($path, 'r');
  my $post = shared_clone({
    path => $path,
    posted => ($file->stat)[10],
    body => join('', $file->getlines),
  });
  
  @news = sort {$b->{posted} <=> $a->{posted}} @news, $post;
}

sub read_news {
  debug 'Scanning news directory';

  my $path = setting('path_news');
  add_news $_ for <$path/*.txt>;
}

sub add_song {
  my $path = shift;

  lock %songs;

  my $mp3 = MP3::Tag->new($path);
  $mp3->get_tags;

  (my $id = sha1_base64($path)) =~ s/\//_/g;

  $songs{$id} = shared_clone({
    id => $id,
    path => $path,
    artist => $mp3->artist,
    title => $mp3->title,
    album => $mp3->album,
    track => $mp3->track1 || 0,
    year => $mp3->year,
  });
}

sub read_songs {
  debug 'Scanning song directory';
  
  find({
    no_chdir => 1,
    wanted => sub { 
      my $type = mimetype($_);

      if ($type and $type eq 'audio/mpeg') {
        add_song($_);
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

sub play {
  debug 'Starting playback thread';

  my $shout = Shout->new(
    host        => 'localhost',
    port        => 8000,
    mount       => 'eatabrick',
    user        => 'source',
    password    => 'afoevb',
    nonblocking => 0,
    dumpfile    => undef,
    name        => 'Eat a Brick Radio',
    url         => 'http://radio.eatabrick.org/',
    genre       => 'Steve',
    description => 'For to be to make you smarter.  For to be to get you dead.',
    format      => SHOUT_FORMAT_MP3,
    protocol    => SHOUT_PROTOCOL_HTTP,
    public      => 1,
  );

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

    my $meta = join ' - ', $song->{artist}, $song->{title};
    my $file = IO::File->new($song->{path}, 'r');
    unless ($file) {
      warning "Unable to open $song->{path}: $!";
      next;
    }

    $shout->set_metadata(song => $meta);
    {
      lock $current;
      $current = $song;
    }

    while (my $frame = MPEG::Audio::Frame->read($file)) {
      threads->yield;

      lock @command;
      if (my $command = shift @command) {
        if ($command eq 'skip') {
          last;
        } elsif ($command eq 'stop') {
          lock $current;
          undef $current;
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
        lock $current; 
        undef $current;
        $shout->close;
        warning 'Sending to shoutcast failed: ' . $shout->get_error;
        return;
      }
    }
  } 
}

# background stuff
threads->create('read_songs')->detach;
threads->create('read_news')->detach;
threads->create('play')->detach;

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

sub analyze_mp3 {
  my $path = shift;
  my $hint = shift;

  my $mp3 = MP3::Tag->new($path) or return undef;
  $mp3->get_tags;

  return {
    path => $path,
    hint => $hint,
    artist => $mp3->artist,
    title => $mp3->title,
    album => $mp3->album,
    track => $mp3->track,
    year => $mp3->year,
    album_artist => $mp3->select_id3v2_frame_by_descr('TPE2'),
  };
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
  my @s = sort {
    $songs{$a}{artist} cmp $songs{$b}{artist} or
    $songs{$a}{album}  cmp $songs{$b}{album}  or
    $songs{$a}{track}  <=> $songs{$b}{track}
  } keys %songs;

  @s = grep {$songs{$_}{artist}   eq params->{artist}}   @s if params->{artist};
  @s = grep {$songs{$_}{album}    eq params->{album}}    @s if params->{album};
  @s = grep {lc $songs{$_}{title} eq lc params->{title}} @s if params->{title};
  
  template 'songs', { songs => [@songs{@s}] };
};

get '/songs/:id.mp3' => sub {
  if (session('user') and my $song = $songs{params->{id}}) {
    content_type 'audio/mpeg';

    my $file = IO::File->new($song->{path}, 'r');
    join '', $file->getlines();
  } else {
    status 'not_found';
    template '404';
  }
};

get '/songs/:id.jpg' => sub {
  if (my $song = $songs{params->{id}}) {
    my $mp3 = MP3::Tag->new($song->{path});
    if (my $art = $mp3->select_id3v2_frame_by_descr('APIC')) {
      $art = $art->{_Data} if ref($art) eq 'HASH';
      my $type = mimetype(IO::String->new($art));
      
      if ($type =~ /^image/) {
        content_type $type;
        return $art;
      } else {
        send_file 'unknown.jpg';
      }
    } else {
      send_file 'unknown.jpg';
    }
  } else {
    status 'not_found';
    template '404';
  }
};

get '/songs/:id' => sub {
  if (my $song = $songs{params->{id}}) {
    template 'song', { 
      song => $song,
      mp3 => MP3::Tag->new($song->{path}),
    };
  } else {
    status 'not_found';
    template '404';
  }
};

post '/songs/enqueue' => sub {
  if (my $song = $songs{params->{id}}) {
    push @queue, $song;
    flash 'Song enqueued';
    redirect '/songs';
  } else {
    status 'not_found';
    template '404';
  }
};

post '/songs/:id' => sub {
  require_login or return;

  if (my $song = $songs{params->{id}}) {
    my @frames = grep /^[A-Z]{4}$/, params;

    my $mp3 = MP3::Tag->new($song->{path});

    $mp3->select_id3v2_frame_by_descr($_, params->{$_}) for @frames;
    $mp3->update_tags;

    flash 'Updated song information';

    redirect '/songs/' . params->{id}; 
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

  my @confirm = ();

  if (my $file = upload('upload')) {
    my $type = mimetype($file->tempname);
    if ($type eq 'audio/mpeg') {
      if (my $song = analyze_mp3($file->tempname, $file->filename)) {
        push @confirm, $song;
      } else {
        flash error => 'Unable to read tags from ' . $file->filename;
      }
    } elsif ($type eq 'application/zip') {
      if (my $zip = Archive::Zip->new($file->tempname)) {
        for my $member ($zip->members) {
          my $data = $zip->contents($member);
          next unless mimetype(IO::String->new($data)) eq 'audio/mpeg';
  
          my $fh = File::Temp->new(UNLINK => 0);
          $fh->print($data);
          $fh->close;
  
          if (my $song = analyze_mp3($fh->filename, $member->fileName)) {
            push @confirm, $song;
          } else {
            flash error => 'Unable to read tags from ' . $member->fileName;
          }
        }
      } else {
        flash error => "Could not process zip archive";
      }
    } else {
      flash warning => "Cannot process $type files";
    }
  } elsif (my $ids = params->{include}) {
    flash warning => 'Not yet implemented';

    $ids = [$ids] unless ref $ids eq 'ARRAY';
    foreach (@$ids) {
      # save tags
      # determine path
      # link file
    }
  }

  template 'upload', { confirm => \@confirm };
};

get '/queue' => sub {
  require_login or return;

  template 'queue', { queue => \@queue };
};

post '/queue/remove' => sub {
  require_login or return;

  my @new = ();
  for (@queue) {
    if ($_->{id} eq params->{id}) {
      flash 'Song remove from queue';
    } else {
      push @new, $_;
    }
  }

  lock @queue;
  @queue = @new;

  redirect '/queue';
};

post '/queue/start' => sub {
  require_login or return;

  if ($current) {
    flash warning => 'Already playing';
  } elsif (%songs) {
    threads->create('play')->detach;
    sleep 1;
    flash 'Playback started';
  } else {
    flash warning => 'No songs to play';
  }

  redirect '/queue';
};

post '/queue/stop' => sub {
  require_login or return;

  if ($current) {
    lock @command;
    push @command, 'stop';
    flash 'Playback stopped';
  } else {
    flash warning => 'Not playing';
  }

  redirect '/queue';
};

post '/queue/rescan' => sub {
  require_login or return;

  read_songs;
  flash 'Music directory rescanned';

  redirect '/queue';
};

post '/queue/skip' => sub {
  require_login or return;

  lock @command;
  push @command, 'skip';

  flash 'Song skipped';

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
