#!/usr/bin/python

import stomp

conn = stomp.Connection10()
conn.start()
conn.connect()
conn.send('SampleQueue', 'Simples Assim')
conn.disconnect()
