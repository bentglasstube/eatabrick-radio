#/bin/env perl

use Dancer;
use interface;

if (setting('daemon')) {
  # daemonize
  open STDIN, '<', '/dev/null' or die "Cannot read /dev/null: $!";

  if (my $logfile = setting('interface')->{logfile}) {
    open STDOUT, '>>', $logfile or die "Cannot write logfile: $!";
  }

  defined( my $pid = fork) or die "Cannot fork: $!";
  exit if $pid;

  open STDERR, '>&STDOUT' or die "Cannot duplicate STDOUT: $!";

  # ignore setting later
  set daemon => undef;
}

if (my $pidfile = setting('interface')->{pidfile}) {
  # save pid to file
  open PIDFILE, '>', $pidfile or die "Cannot write pidfile: $!";
  print PIDFILE $$;
  close PIDFILE;
}

if (my $port = setting('interface')->{port}) {
  set port => $port;
}

# startup processes
interface::read_songs_in_background;
interface::read_news;

# launch interface
dance;
