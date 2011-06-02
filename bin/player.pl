#/bin/env perl

use Dancer;
use player;

if (setting('daemon')) {
  # daemonize
  open STDIN, '<', '/dev/null' or die "Cannot read /dev/null: $!";

  if (my $logfile = setting('player')->{logfile}) {
    open STDOUT, '>>', $logfile or die "Cannot write logfile: $!";
  }

  defined( my $pid = fork) or die "Cannot fork: $!";
  exit if $pid;

  open STDERR, '>&STDOUT' or die "Cannot duplicate STDOUT: $!";

  # ignore setting later
  set daemon => undef;
}

if (my $pidfile = setting('player')->{pidfile}) {
  # save pid to file
  open PIDFILE, '>', $pidfile or die "Cannot write pidfile: $!";
  print PIDFILE $$;
  close PIDFILE;
}

if (my $port = setting('player')->{port}) {
  set port => $port;
}

# startup processes
player::read_songs;
player::start_playback;

# launch player
dance;
