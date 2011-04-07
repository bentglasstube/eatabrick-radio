package radio;

use strict;
use warnings;

use Dancer ':syntax';
use Dancer::Plugin::Database;
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
    select song.*
    from song
    where title like ?
  });
  
  my $songs = [];

  if (params->{q}) {
    $sth->execute('%' . params->{q} . '%');
    $songs = $sth->fetchall_arrayref({});
    $sth->finish();
  }

  template 'request', { songs => $songs };
};

post '/request' => sub {
};

get '/login' => sub { 
  template 'login' 
};

get '/logout' => sub {
  if (my $user = authenticate(params->{name}, params->{pass})) {
    flash 'Welcome, ' . $user->name . '.';

    my $uri = session('requested_page') || '/';
    
    session(requested_page => undef);
    session(user => $user);
    
    redirect $uri;
  } else {
    flash error => 'Invalid credentials.';
    redirect '/login';
  }
};

post '/login' => sub {
  session(user => undef);
  flash 'You have been logged out.';
  redirect '/';
};

prefix '/admin';

get '/queue' => sub { 
  template 'queue';
};

get '/songs' => sub { 
  template 'songs';
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
