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
  return if session('user');
  
  flash warning => 'You must log in to view this page.';
  session(requested_page => request->path_info);
  
  redirect '/login';
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

  $sth->finish();
};

get '/' => sub { 
  template 'news';
};

get '/songs' => sub {
  my @constraints = ();
  my @params = ();

  if (params->{q}) {
    push @constraints, 'title like ?';
    push @params, '%' . params->{q}, '%';
  }

  if (params->{queue}) {
    push @constraints, 'queue.position is not null';
  }

  my $constraints = join(' and ', @constraints) || 1;

  my $sth_count = query(q{
    select count(song.id)
    from song
    left join queue on queue.song_id = song.id
    where %s
  }, $constraints);

  my $sth_data = query(q{
    select song.id, song.title, song.last_played, queue.position 
    from song 
    left join queue on queue.song_id = song.id
    where %s
    order by title asc
    limit ?, ?
  }, $constraints);

  $sth_count->execute(@params);
  my ($count) = $sth_count->fetchrow_array();
  $sth_count->finish();

  push @params, 5 * ((params->{page} || 1) - 1), 5;

  $sth_data->execute(@params);
  my $songs = $sth_data->fetchall_arrayref({});
  $sth_data->finish();

  $_->{ago} = ago($_->{last_played}) for @$songs;

  template 'songs', { 
    songs => $songs,
    pager => {
      current => params->{page} || 1,
      last => floor($count / 5),
    }, 
  };
};

get '/upload' => sub { 
  template 'upload';
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
any qr{.*} => sub { status 'not_found'; template '404' };

true;
