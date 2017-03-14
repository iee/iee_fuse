#!/usr/bin/python

from stompy.simple import Client
import json

Dict_Message = dict()
Dict_Message["Test1"] = "CONDOR"

stomp = Client("localhost", 61613)
stomp.connect("producer", "pass")
stomp.put(json.dumps(Dict_Message), destination="/queue/test",conf={'Test':'Test123'})
stomp.disconnect()

stomp = Client("localhost", 61613)
stomp.connect("consumer", "pass")
stomp.subscribe("/queue/test",conf={'selector' : "Test = 'Test123'"})
#stomp.subscribe("/queue/test")
message = stomp.get()

print message.headers
New_Dict = json.loads(message.body)
print New_Dict
stomp.ack(message)
stomp.unsubscribe("/queue/test")
stomp.disconnect()
