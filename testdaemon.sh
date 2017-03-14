#! /bin/bash
# Copyright (c) 1996-2012 My Company.
# All rights reserved.
#
# Author: Bob Bobson, 2012
#
# Please send feedback to bob@bob.com
#
# /etc/init.d/testdaemon
#
### BEGIN INIT INFO
# Provides: testdaemon
# Required-Start: $all
# Required-Stop:
# Should-Stop:
# Should-Start: activemq
# Default-Start:  3 4 5
# Default-Stop:   0 1 2 6
# Short-Description: Test daemon process
# Description:    Runs up the test daemon process
### END INIT INFO

# Activate the python virtual environment
source /opt/testdaemon/venv/bin/activate

case "$1" in
  start)
    echo "Starting server"
    # Start the daemon 
    python /opt/testdaemon/testdaemon.py start
    ;;
  stop)
    echo "Stopping server"
    # Stop the daemon
    python /opt/testdaemon/testdaemon.py stop
    ;;
  restart)
    echo "Restarting server"
    python /opt/testdaemon/testdaemon.py restart
    ;;
  *)
    # Refuse to do other stuff
    echo "Usage: /etc/init.d/testdaemon.sh {start|stop|restart}"
    exit 1
    ;;
esac

exit 0
