package radio;

use strict;
use warnings;

use Dancer ':syntax';
use Dancer::Plugin::Database;
use POSIX qw(ceil floor);
use Digest::SHA1 'sha1_base64';

our $VERSION = '0.1';

# utilities

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

sub digest {
  my ($salt, $value) = @_;
  
  return sha1_base64(join '::', $salt, setting('salt_key'), $value);
}

sub query {
  my $sql = shift;

  database->prepare_cached(sprintf($sql, @_));
}

sub authenticate {
  my ($name, $password) = @_;
  
  my $sth = query('select * from user where name = ?');
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

  return 'Never' unless $timestamp;

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

before_template sub {
  my $tokens = shift;
  
  my $sth = query(q{
    select song.title
    from queue
    inner join song on queue.song_id = song.id
    where queue.position = 0
  });
  $sth->execute();
  
  $tokens->{now_playing} = ($sth->fetchrow_array())[0];
  $tokens->{ago} = \&ago;

  $sth->finish();
};

get '/' => sub { 
  my $sth = query(q{
    select user.name, news.posted, news.body
    from news 
    inner join user on user.id = news.author
    order by news.posted desc 
    limit 5
  });
  
  $sth->execute();
  my $news = $sth->fetchall_arrayref({});
  $sth->finish();

  template 'news', { posts => $news };
};

post '/' => sub {
  require_login or return;

  my $sth = query('insert into news (author, posted, body) values (?, ?, ?)');

  $sth->execute(session->{user}{id}, time, params->{post});
  $sth->finish();

  flash 'News posted';

  redirect '/';
};

get '/songs' => sub {
  my @constraints = ();
  my @params = ();

  if (params->{q}) {
    push @constraints, 'title like ?';
    push @params, '%' . params->{q} . '%';
  }

  if (params->{queue}) {
    push @constraints, 'queue.position > 0';
  }

  if (params->{never}) {
    push @constraints, 'song.last_played = 0';
  }

  if (params->{min_ago}) {
    push @constraints, 'song.last_played < ?';
    push @params, time() - params->{min_ago} * params->{min_ago_units};
  }

  if (params->{max_ago}) {
    push @constraints, 'song.last_played > ?';
    push @params, time() - params->{max_ago} * params->{max_ago_units};
  }

  my $constraints = join(' and ', @constraints) || 1;

  my $sth = query(q{
    select song.id, song.title, song.last_played, queue.position 
    from song 
    left join queue on queue.song_id = song.id
    where %s
    order by title asc
  }, $constraints);

  $sth->execute(@params);
  my $songs = $sth->fetchall_arrayref({});
  $sth->finish();

  template 'songs', {songs => $songs};
};

get '/songs/:id' => sub {
  my $sth = query(q{
    select song.title, song.last_played, queue.position
    from song
    left join queue on queue.song_id = song.id
    where song.id = ?
  });
  
  $sth->execute(params->{id});
  my $song = $sth->fetchrow_hashref();
  $sth->finish();

  unless ($song) {
    status 'not_found';
    template '404';
    return;
  }

  template 'song', { song => $song };
};

post '/songs/:id' => sub {
  require_login or return;

  my $sth = query('update song set title = ? where id = ?');
  $sth->execute(params->{title}, params->{id});
  $sth->finish;

  flash 'Song renamed.';

  redirect '/songs/' . params->{id}; 
};

get '/upload' => sub { 
  require_login or return;

  template 'upload';
};

post '/upload' => sub {
  require_login or return;

  flash warning => 'Uploading is not yet implemented.';

  redirect '/upload';
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

# default route (404)
any qr{.*} => sub { 
  status 'not_found'; 
  template '404';
};

true;
