package radio;

use strict;
use warnings;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;

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
  
  my $user = schema->resultset('User')->find({name => $name}) or return undef;
  
  if ($user->pass eq digest($user->salt, $password)) {
    return $user;
  } else {
    return undef;
  }
}

sub search {
  my ($set, $attribute, $value) = @_;
  
  my @results = schema->resultset($set)->search({
    $attribute, { like => "%$value%" }
  });
}

# Routes
before sub { require_login if request->path_info =~ m{^/admin} };
before_template sub {
  # add now playing song to each request
  my ($tokens) = @_;
  
  $tokens->{now_playing} = 'test';
  # schema->resultset('Queue')->find({ position => 0 })->song->title;
};

# public interface
get  '/'        => sub { template 'news' };
get  '/listen'  => sub { redirect setting 'stream_uri' };
get  '/request' => sub { template 'request' };
post '/request' => \&do_request;

# session management
get  '/login'   => sub { template 'login' };
get  '/logout'  => \&do_logout;
post '/login'   => \&do_login;

# administrative interface
prefix '/admin';
get  '/queue'   => sub { template 'queue' };
get  '/songs'   => sub { template 'songs' };
get  '/upload'  => sub { template 'upload' };
get  '/post'    => sub { template 'post' };

# default route (404)
prefix undef;
any qr{.*} => sub { status 'not_found'; template '404' };

# handlers

sub do_login {
  if (my $user = authenticate(params->{name}, params->{pass})) {
    flash 'Welcome, ' . $user->name . '.';

    my $uri = session('requested_page') || '/admin';
    
    session(requested_page => undef);
    session(user => $user);
    
    redirect $uri;
  } else {
    flash error => 'Invalid credentials.';
    redirect '/login';
  }
}

sub do_logout {
  session(user => undef);
  flash 'You have been logged out.';
  redirect '/';
}

sub do_request {
  
}

true;
