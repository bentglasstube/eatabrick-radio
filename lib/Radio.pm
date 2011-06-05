package Radio;

use strict;
use warnings;

use Dancer ':syntax';
use Dancer::Plugin::MPD;

use IO::File;
use POSIX qw(ceil);
use Time::Piece;
use Radio::Station;

our $VERSION = '0.1';
our $station = Radio::Station->promote(mpd); 

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
  
  return $pass eq setting('admin_password');
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

before_template sub {
  my $tokens = shift;
  
  $tokens->{current} = $station->current; 
  $tokens->{ago} = \&ago;
  $tokens->{stream_uri} = setting('stream_uri');
};

get '/' => sub { 
  template 'news', { posts => [] };
};

get '/index.html' => sub {
  template 'news', { posts => [] };
};

post '/' => sub {
  require_login or return;

  my $id = localtime->strftime('%Y%m%d.%H%M%S');

  my $path = setting('path_news') . "/$id.txt";
  my $file = IO::File->new($path, 'w');

  if ($file) {
    $file->print(params->{post});
    $file->close();
    flash 'News posted';
  } else {
    flash error => "Unable to open news file $path: $!";
  }

  redirect '/';
};

get '/songs' => sub {
  if (my $q = params->{search}) {
    template 'songs', { songs => [] };
  } else {
    template 'albums', { albums => $station->albums };
  }
};

get '/songs/:album.png' => sub {
  if (my $album = $station->album(params->{album})) {
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
  if (my $album = $station->album(params->{album})) {
    template 'tracks', { album => $album };
  } else {
    status 'not_found';
    template '404';
  }
};

post '/songs/:album' => sub {
  if (my $album = $station->album(params->{album})) {
    if (params->{enqueue}) {
      require_login or return;
      $station->enqueue(grep {$_} @{$album->{tracks}});
      flash 'Album added to queue';
    }

    redirect "/songs/$album->{uri}";
  } else {
    status 'not_found';
    template '404';
  }

};

get '/songs/:album/:n' => sub {
  if (my $song = $station->song(params->{album}, params->{n})) {
    template 'song', { 
      song => $song,
    };
  } else {
    status 'not_found';
    template '404';
  }
};

post '/songs/:album/:n' => sub {
  if (my $song = $station->song(params->{album}, params->{n})) {
    if (params->{enqueue}) {
      $station->enqueue($song);
      flash 'Song added to the queue';
    }
    redirect "/songs/$song->{uri}";
  } else {
    status 'not_found';
    template '404';
  }
};

get '/queue' => sub {
  template 'queue', { queue => $station->queue };
};

post '/queue' => sub {
  require_login or return;

  if (params->{rescan}) {
    $station->updatedb();
    flash 'Rescanning music directory';
  } elsif (params->{skip}) {
    $station->next();
    flash 'Song skipped';
  } elsif (params->{start}) {
    $station->play();
    flash 'Playback started';
  } elsif (params->{stop}) {
    $station->stop();
    flash 'Playback stopped';
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

# fork for queue management thrad
my $pid = fork();
if (!defined $pid) {
  die "Failed to fork queue manager";
} elsif ($pid == 0) {
  require Radio::QueueManager;
  Radio::QueueManager::manage();
} else {
  debug "Forked queue manager $pid";
}

true;
