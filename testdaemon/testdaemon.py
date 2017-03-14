#!/usr/bin/env python
# To kick off the script, run the following from the python directory:
#   PYTHONPATH=`pwd` python testdaemon.py start
# -*- coding: utf-8 -*-
from __future__ import unicode_literals

import logging
import time
import stomp
import smbutil
import json

#third party libs
from daemon import runner



class SampleListener(object):
    def on_message(self, headers, msg):
       #logger.info(msg)
       parsed_string = json.loads(msg)
       logger.info(parsed_string["Function"])
       logger.info(parsed_string["Parameters"])
       method_name = 'number_' + str(parsed_string["Function"])
       method = getattr(self, method_name, lambda: "nothing")
       method(parsed_string["Parameters"])

    def number_0(self, parms):
        for status in parms:
            smbutil.set_sd(status)
            logger.info(status)

    def number_1(self, parms):
        for item in parms:
            smbutil.set_sd_from_parent(item)
            logger.error(item)

    def number_2(self, parms):
        for item in parms:
            smbutil.set_tree_ntacl(item)
            logger.error(item)

    def number_4(self, parms):
        for item in parms:
            smbutil.recalcExistingFolder(item)

class App():
    
    def __init__(self):
        self.stdin_path = '/dev/null'
        self.stdout_path = '/opt/testdaemon/test2.txt'
        self.stderr_path = '/opt/testdaemon/test.txt'
        self.pidfile_path =  '/var/run/testdaemon.pid'
        self.pidfile_timeout = 5

    def run(self):
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

app = App()
logger = logging.getLogger("DaemonLog")
logger.setLevel(logging.INFO)
formatter = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
handler = logging.FileHandler("/var/log/testdaemon/testdaemon.log")
handler.setFormatter(formatter)
logger.addHandler(handler)

daemon_runner = runner.DaemonRunner(app)
#This ensures that the logger file handle does not get closed during daemonization
daemon_runner.daemon_context.files_preserve=[handler.stream]
daemon_runner.do_action()

