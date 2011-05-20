#! /bin/sh

### BEGIN INIT INFO
# Provides:          Eat a Brick Radio
# Required-Start:    $all
# Required-Stop:     $all
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Starts Eat a Brick Radio
# Description:       Starts Eat a Brick Radio using start-stop-daemon
### END INIT INFO

############### EDIT ME ##################
# path to app
APP_PATH=/home/alan/eatabrick-radio/

# path to perl binary
DAEMON=/usr/bin/perl

# Path to store PID file
PID_FILE=/var/run/eatabrick-radio/run.pid
PID_PATH=`dirname $PID_FILE`

# startup args
DAEMON_OPTS="bin/app.pl 2>>/var/log/eatabrick-radio.log &"

# script name
NAME=eatabrick-radio

# app name
DESC="Eat a Brick Radio"

# user
RUN_AS=alan

############### END EDIT ME ##################

test -x $DAEMON || exit 0

set -e

if [ ! -d $PID_PATH ]; then
        mkdir -p $PID_PATH
        chown $RUN_AS $PID_PATH
fi

case "$1" in
  start)
        echo "Starting $DESC"
        start-stop-daemon -d $APP_PATH -c $RUN_AS --start --pidfile $PID_FILE --exec $DAEMON -- $DAEMON_OPTS
        ;;
  stop)
        echo "Stopping $DESC"
        start-stop-daemon --stop --pidfile $PID_FILE
        ;;

  restart|force-reload)
        echo "Restarting $DESC"
        start-stop-daemon --stop --pidfile $PID_FILE
        sleep 15
        start-stop-daemon -d $APP_PATH -c $RUN_AS --start --pidfile $PID_FILE --exec $DAEMON -- $DAEMON_OPTS
        ;;
  *)
        N=/etc/init.d/$NAME
        echo "Usage: $N {start|stop|restart|force-reload}" >&2
        exit 1
        ;;
esac

exit 0
