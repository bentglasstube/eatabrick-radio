package radio;

use strict;
use warnings;

use Dancer ':syntax';
use Dancer::Plugin::Database;
use POSIX qw(ceil);
use Digest::SHA1 'sha1_base64';

our $VERSION = '0.1';

# utilities

sub flash { 
  my $type = @_ > 1 ? shift : '';
  my $message = shift;
  
  session->{flash}{$message} = $type;
}

sub require_login {
  return if session('user');
  
  flash warning => 'You must log in to view this page.';
  session(requested_page => request->path_info);
  
  redirect '/login';
}

sub digest {
  my ($salt, $value) = @_;
  
  return sha1_base64(join '::', $salt, setting('salt_key'), $value);
}

sub authenticate {
  my ($name, $password) = @_;
  
  my $sth = database->prepare_cached('select * from user where name = ?');
  $sth->execute($name);

  my $user = $sth->fetchrow_hashref or return undef;

  $sth->finish();

  if ($user->{pass} eq digest($user->{salt}, $password)) {
    return $user;
  } else {
    return undef;
  }
}

sub ago {
  my $timestamp = shift;

  my $now = time;
  my $minutes = int(($now - $timestamp) / 60);

  my $count = 0;
  my $unit = 'minute';

  if ($minutes < 55) {
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

  return sprintf('%u %s%s ago', $count, $unit, $count > 1 ? 's' : '');
}

before sub { 
  require_login if request->path_info =~ m{^/admin} 
};

before_template sub {
  my $tokens = shift;
  
  my $sth = database->prepare_cached(q{
    select song.title
    from queue
    inner join song on queue.song_id = song.id
    where queue.position = 0
  });
  $sth->execute();
  
  $tokens->{now_playing} = ($sth->fetchrow_array())[0];

  $sth->finish();
};

get '/' => sub { 
  template 'news';
};

get '/request' => sub { 
  my $sth = database->prepare_cached(q{
    select * 
    from song 
    where title like ?
    order by title asc
  });
  
  my $songs = [];

  if (params->{q}) {
    $sth->execute('%' . params->{q} . '%');
    $songs = $sth->fetchall_arrayref({});
    $sth->finish();
  }

  $_->{ago} = ago($_->{last_played}) for @$songs;

  template 'request', { songs => $songs };
};

post '/request' => sub {
  my $sth = database->prepare_cached('select * from song where id = ?');

  $sth->execute(params->{id});

  if (my $song = $sth->fetchrow_hashref()) {
    my $ago = time - $song->{last_played};
    if ($ago < 3600) {
      flash error => 'That song has been played too recently.';
    } else {
      # enqueue_song
      flash 'Song added to queue.';
    }
  } else {
    flash error => 'Invalid song.';
  }
  
  $sth->finish();

  redirect '/request';
};

get '/login' => sub { 
  template 'login' 
};

post '/login' => sub {
  if (my $user = authenticate(params->{name}, params->{pass})) {
    flash 'Welcome, ' . $user->{name} . '.';

    my $uri = session('requested_page') || '/';
    
    session(requested_page => undef);
    session(user => $user);
    
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

prefix '/admin';

get '/queue' => sub { 
  my $sth = database->prepare_cached(q{
    select queue.position, song.id, song.title
    from queue
    inner join song on queue.song_id = song.id
    order by queue.position asc
  });

  $sth->execute();
  my $queue = $sth->fetchall_arrayref({});
  $sth->finish();

  template 'queue', { queue => $queue };
};

get '/songs' => sub {
  my $sth = database->prepare_cached(q{
    select * 
    from song 
    where title like ?
    order by title asc
  });

  my $search = params->{q} ? '%' . params->{q} . '%' : '%';
  $sth->execute($search);
  my $songs = $sth->fetchall_arrayref({});
  $sth->finish();

  $_->{ago} = ago($_->{last_played}) for @$songs;

  template 'songs', { songs => $songs };
};

get '/upload' => sub { 
  template 'upload';
};

get '/post' => sub { 
  template 'post';
};

# default route (404)
prefix undef;
any qr{.*} => sub { status 'not_found'; template '404' };

true;
