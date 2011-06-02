package interface;

use strict;
use warnings;

use Dancer ':syntax';

use threads;
use threads::shared;

use File::MimeInfo::Magic;
use File::Find;
use MP3::Tag;
use IO::File;
use IO::String;
use POSIX qw(ceil);
use Digest::SHA1 'sha1_base64';
use LWP::UserAgent;

our $VERSION = '0.1';

our %songs   :shared = ();
our %albums  :shared = ();
our @news            = ();
our $ua              = LWP::UserAgent->new;
our $scanner         = undef;

MP3::Tag->config(autoinfo => 'ID3v2');

sub urlify {
  my $string = lc shift;
  $string =~ s/[^a-z0-9]+/_/g;
  return $string;
}

sub player_get {
  my $path = shift || '';

  my $response = $ua->get(setting('player_uri') . $path);
  if ($response->is_success) {
    return split /\n/, $response->content;
  }

  return ();
}

sub player_post {
  my $path = shift;
  my $data = shift || {};

  my $response = $ua->post(setting('player_uri') . $path, $data);
  if ($response->is_success) {
    return split /\n/, $response->content;
  }

  return ();
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

  my $song = shared_clone({
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
    $albums{$album_id}{songs}[$song->{track}] = $songs{$path} = $song;
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

sub read_songs_in_background {
  return if $scanner and $scanner->is_running;
  $scanner = threads->create('read_songs');
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
  
  return $pass eq setting('interface')->{password};
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

sub skip_song {
  player_post('skip');
  flash 'Song skipped';
}

sub enqueue_song {
  my $path = shift;
  player_post('queue', { path => $path });
}

sub current_song {
  if (my ($path) = player_get) {
    if (my $song = $songs{$path}) {
      return $song;
    } else {
      warning "Couldn't find song matching $path";
    }
  } else {
    return undef;
  }
}

sub get_queue {
  my @paths = player_get('queue');

  debug $_ for @paths;
  return [map $songs{$_}, @paths];
}

before_template sub {
  my $tokens = shift;
  
  $tokens->{current} = current_song; 
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

get '/songs' => sub {
  flash warning => 'Music scan in progress' if $scanner && $scanner->is_running;

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
  flash warning => 'Music scan in progress' if $scanner && $scanner->is_running;

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
      enqueue_song $_->{path} for grep { defined $_ } @{$album->{songs}};
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
      enqueue_song $song->{path};
      flash 'Song added to the queue';
    }
    redirect $song->{uri};
  } else {
    status 'not_found';
    template '404';
  }
};

get '/queue' => sub {
  template 'queue', { queue => get_queue };
};

post '/queue' => sub {
  require_login or return;

  if (params->{rescan}) {
    read_songs_in_background;
    player_post('reload');
    flash 'Rescanning music directory';
  } elsif (params->{skip}) {
    skip_song();
    flash 'Song skipped';
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
