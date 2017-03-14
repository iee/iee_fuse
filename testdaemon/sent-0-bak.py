#! /usr/bin/env python
# -*- coding: utf-8 -*-
from __future__ import unicode_literals

import stomp
import json

json_string = json.dumps({
	"Function": 0,
	"Parameters": [{
		"FolderID": 4,
		"Inherited": "True",
		"Owner": "shheblykinn",
		"Group": "Геореконструкция",
		"ACL": [{
			"Name": "система",
			"Right": "FULL"
		}, {
			"Name": "venediktovai",
			"Right": "WRITE"
		}, {
			"Name": "Геореконструкция",
			"Right": "READ"
		}]
	}]
})

conn = stomp.Connection10()
conn.start()
conn.connect()
conn.send('SampleQueue', json_string)
conn.disconnect()
