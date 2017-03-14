#! /usr/bin/env python
# -*- coding: utf-8 -*-
from __future__ import unicode_literals

import stomp
import json

json_string = json.dumps({
	"Function": 3,
	"Parameters": [{
		"FolderID": 33195
	}]
})

conn = stomp.Connection10()
conn.start()
conn.connect()
conn.send('SampleQueue', json_string)
conn.disconnect()
