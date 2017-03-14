# -*- coding: utf-8 -*-

import os
import codecs
import psycopg2
from samba.param import LoadParm
from samba.ntacls import setntacl, getntacl, XattrBackendError
import samba.xattr_native, samba.xattr_tdb, samba.posix_eadb
from samba.dcerpc import security, xattr, idmap
from samba.ndr import ndr_pack, ndr_unpack
from samba.samba3 import smbd

class XattrBackendError(Exception):
    """A generic xattr backend error."""

def t(dir_id,sddl):
	print('start!')
	
	#sddl = "O:SYG:S-1-5-21-3874029520-2253553080-878871061-1113D:PAI(A;OICI;0x001f01ff;;;SY)(A;OICI;0x001201ff;;;S-1-5-21-3874029520-2253553080-878871061-1118)"
	print(sddl)	
	
	sddl_sub_folder = sddl.replace("D:PAI", "D:AI").replace("A;OICI","A;OICIID");
	print(sddl_sub_folder)
	
	sddl_file = sddl.replace("D:PAI", "D:AI").replace("A;OICI","A;ID");
	print(sddl_file)
	
	sid = security.dom_sid("S-1-5-21-3874029520-2253553080-878871061")
	print(str(sid))
	
	## root sd
	sd_root = security.descriptor.from_sddl(sddl, sid)
	
	ntacl_root = xattr.NTACL()
	ntacl_root.version = 1
	ntacl_root.info = sd_root
	ndrpack_root = ndr_pack(ntacl_root)
	#print(type(ndrpack))
	
	# sub folder
	sd_subfolder = security.descriptor.from_sddl(sddl_sub_folder, sid)
	
	ntacl_subfolder = xattr.NTACL()
	ntacl_subfolder.version = 1
	ntacl_subfolder.info = sd_subfolder
	ndrpack_subfolder = ndr_pack(ntacl_subfolder)
	
	# file
	sd_file = security.descriptor.from_sddl(sddl_file, sid)
	
	ntacl_file = xattr.NTACL()
	ntacl_file.version = 1
	ntacl_file.info = sd_file
	ndrpack_file = ndr_pack(ntacl_file)

	try:
		conn = psycopg2.connect("dbname='lportal' user='postgres' host='localhost' password='Qwertyu*'")
	except:
		print "I am unable to connect to the database."

	qid=dir_id #1603237
	cur = conn.cursor()
	try:
		cur.callproc("func_update_ntacl", (qid, psycopg2.Binary(ndrpack_root), psycopg2.Binary(ndrpack_subfolder), psycopg2.Binary(ndrpack_file), ))
	except:
		print "I can't call func_update_ntacl"
	
	conn.commit()
	cur.close()

	cur = conn.cursor()
	try:
		cur.callproc("func_get_tree", (qid, ))
	except:
		print "I can't call func_update_ntacl"

	conn.commit()
	
	ids = cur.fetchone()[0];
	
	cur.close()
	conn.close()

	import redis
	
	r = redis.StrictRedis(host='localhost', port=6379, db=0)

	for x in ids.split(" "):
		r.delete(x)



