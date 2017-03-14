#! /usr/bin/env python
# -*- coding: utf-8 -*-
from __future__ import unicode_literals

import stomp
import json

json_string = json.dumps({
	"Function": 1,
	"Parameters": [{
		"ItemID": 5,
		"Directory": "True"
	}, {
                "ItemID": 9223372036854775806,
                "Directory": "False"
        }]
})

conn = stomp.Connection10()
conn.start()
conn.connect()
conn.send('SampleQueue', json_string)
conn.disconnect()
