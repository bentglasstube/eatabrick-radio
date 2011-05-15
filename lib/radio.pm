package radio;

use strict;
use warnings;

use Dancer ':syntax';

use POSIX qw(ceil floor);

use Digest::SHA1 'sha1_base64';

use File::MimeInfo;
use File::Basename;
use MP3::Tag;
use IO::File;

our $VERSION = '0.1';

our %songs = ();
our @queue = ();
our @news  = ();

sub add_news {
  my $path = shift;

  my $file = IO::File->new($path, 'r');
  my $post = {
    id => basename($path, '.txt'),
    posted => ($file->stat)[10],
    body => join('', $file->getlines),
  };
  
  @news = sort {$b->{posted} <=> $a->{posted}} @news, $post;
}

sub read_news {
  my $path = setting('path_news');
  add_news $_ for <$path/*.txt>;
}

sub add_song {
  my $path = shift;

  my $mp3 = MP3::Tag->new($path);
  $mp3->get_tags;

  my $id = basename($path, '.mp3');

  $songs{$id} = {
    id => $id,
    path => $path,
    title => join(' - ', $mp3->artist, $mp3->title),
    last_played => 0,
    mp3 => $mp3,
  };
}

sub read_songs {
  my $path = setting('path_songs');
  add_song $_ for <$path/*.mp3>;
}

sub generate_id {
  my $id = sha1_base64(join '::', rand, time);
  $id =~ s/\//_/g;

  return $id;
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

sub get_current_song {
  return undef;
}

sub get_song_list {
  my $q = shift;

  return [@songs{grep {$songs{$_}{title} =~ /\Q$q\E/i} keys %songs}] if $q;
  return [@songs{keys %songs}];
}

before_template sub {
  my $tokens = shift;
  
  $tokens->{now_playing} = get_current_song();
  $tokens->{ago} = \&ago;
};

get '/' => sub { 
  template 'news', { posts => \@news };
};

post '/' => sub {
  require_login or return;

  my $id = generate_id();

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

  my $path = setting('path_news') . '/' . params->{id};

  if (unlink $path) {
    flash 'Post deleted';
    @news = grep {$_->{id} ne params->{id}} @news;
  } else {
    flash error => "Could not delete post: $!";
  }

  redirect '/';
};

get '/songs' => sub {
  template 'songs', { songs => get_song_list(params->{q}) };
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

get '/songs/:id.png' => sub {
  if (my $song = $songs{params->{id}}) {
    if (my $art = $song->select_id3v2_frame_by_descr('APIC')) {
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
    template 'song', { song => $song };
  } else {
    debug 'No song with id ' . params->{id};
    status 'not_found';
    template '404';
  }
};

post '/songs/:id' => sub {
  require_login or return;

  if (my $song = $songs{params->{id}}) {
    my @frames = grep /T.../, params;

    $song->{mp3}->select_id3v2_frame_by_descr($_, params->{$_}) for @frames;
    $song->{mp3}->update_tags;

    $song->{title} = join ' - ', $song->{mp3}->artist, $song->{mp3}->title;

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

  if (my $file = upload('upload')) {
    # check mime type
    my $type = mimetype($file->tempname);
    if ($type eq 'audio/mpeg') {
      # link the song and call it a day
      my $id = generate_id;
      my $path = setting('path_songs') . "/$id.mp3";

      $file->link_to($path);
      add_song($path);

      flash 'Song added.';
      redirect "/songs/$id";
    } else {
      flash warning => "Cannot process $type files.";
      redirect '/upload';
    }
  } else {
    redirect '/upload';
  }
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
    flash error => 'Invalid credentials.';
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

read_songs;
read_news;

# play;

true;
