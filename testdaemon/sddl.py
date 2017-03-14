#! /usr/bin/python2.7
# -*- coding: utf-8 -*-
from __future__ import unicode_literals

import os
import sys
import re

str = "O:SYG:S-1-5-21-3874029520-2253553080-878871061-1118D:AI(A:OICIID;0x001200a9;;;S-1-5-21-3874029520-2253553080-878871061-1118)(A:OICIID;0x001f01ff;;;SY)"
pat = "S\-[0-9]\-[0-9]\-[0-9]{2}\-[0-9]{10}\-[0-9]{10}\-[0-9]{9}"
result = re.findall(pat, str)
print result[0]