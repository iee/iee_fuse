#!/usr/bin/env python
# To kick off the script, run the following from the python directory:
#   PYTHONPATH=`pwd` python testdaemon.py start
# -*- coding: utf-8 -*-
from __future__ import unicode_literals

import sys
import time
import stomp
import smbutil
import json

#third party libs


class SampleListener(object):
    def on_message(self, headers, msg):
       #logger.info(msg)
       parsed_string = json.loads(msg)
       method_name = 'number_' + str(parsed_string["Function"])
       method = getattr(self, method_name, lambda: "nothing")
       method(parsed_string["Parameters"])

    def number_0(self, parms):
        for status in parms:
            smbutil.set_sd(status)

    def number_1(self, parms):
        for item in parms:
            smbutil.set_sd_from_parent(item)

    def number_2(self, parms):
        for item in parms:
            smbutil.set_tree_ntacl(item)

    def number_4(self, parms):
        for item in parms:
            smbutil.recalcExistingFolder(item)

if __name__ == "__main__":
        conn = stomp.Connection10()
        conn.set_listener('SampleListener', SampleListener())
        conn.start()
        conn.connect()
        conn.subscribe('SampleQueue')
        while True:
            #Main code goes here ...
            #Note that logger level needs to be set to logging.DEBUG before this shows up in the logs
            #logger.debug("Debug message")
            #logger.info("Info message")
            #logger.warn("Warning message")
            #logger.error("Error message")
            time.sleep(3)

