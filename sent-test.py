#!/usr/bin/python

import time
import sys
import stomp
from stomp import ConnectionListener


class MyListener(ConnectionListener):
    def on_error(self, headers, message):
        print 'received an error %s' % message

    def onMessage(self, headers, message):
        print headers
        print str(message)
        print type(message)
        print 'received a message ...%s...' % message

conn = stomp.Connection()
conn.set_listener('', MyListener())
conn.start()
conn.connect('admin', 'password', wait=True)
conn.subscribe(destination='/queue/test', id=1, ack='auto')

while 1:
 time.sleep(2)

