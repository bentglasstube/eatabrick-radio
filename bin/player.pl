#/bin/env perl

# parse custom settings first
BEGIN {
  use vars qw($logfile $pidfile);
  my @rest = ();

  while (my $arg = shift @ARGV) {
    if ($arg eq '--logfile') {
      $logfile = shift @ARGV;
    } elsif ($arg eq '--pidfile') {
      $pidfile = shift @ARGV;
    } else {
      push @rest, $arg;
    }
  }

  @ARGV = @rest;
}
  
use Dancer;
use player;

if (setting('daemon')) {
  # daemonize
  open STDIN, '<', '/dev/null' or die "Cannot read /dev/null: $!";

  if ($logfile) {
    open STDOUT, '>>', $logfile or die "Cannot write logfile: $!";
  } else {
    open STDOUT, '>/dev/null' or die "Cannot write /dev/null: $!";
  }

  defined( my $pid = fork) or die "Cannot fork: $!";
  exit if $pid;

  open STDERR, '>&STDOUT' or die "Cannot duplicate STDOUT: $!";

  if ($pidfile) {
    # save pid to file
    open PIDFILE, '>', $pidfile or die "Cannot write pidfile: $!";
    print PIDFILE $$;
    close PIDFILE;

    $SIG{INT} = $SIG{TERM} = sub {
      unlink $pidfile or die "Cannot unlink pidfile: $!";
      exit;
    }
  }

  # ignore setting later
  set daemon => undef;
}

if (my $port = setting('player')->{port}) {
  set port => $port;
}

# startup processes
player::read_songs;
player::start_playback;

# launch player
dance;
