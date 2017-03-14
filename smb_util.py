#! /usr/bin/python2.7
# -*- coding: utf-8 -*-

import os
import sys
import codecs
import psycopg2
import redis
#from psycopg2cffi import compat
#compat.register()
from samba.param import LoadParm
from samba.ntacls import setntacl, getntacl, XattrBackendError
import samba.xattr_native, samba.xattr_tdb, samba.posix_eadb
from samba.dcerpc import security, xattr, idmap
from samba.ndr import ndr_pack, ndr_unpack
from samba.samba3 import smbd

def set_acl(path, sddl):

	print('start set_acl!')
	print(path)
	print(sddl)
	
	sid = security.dom_sid("S-1-5-21-3874029520-2253553080-878871061")
	print(sid)
	try:
		lp = LoadParm()
		setntacl(lp, path, sddl, sid)
	except Exception, e:
		print str(e)
	
	print('finish set_acl!')

def set_acl_from_root2(id, isDir, path):

	print('start set_acl_from_root2!')
	
	print(id)	
	print(path)
	
	sid = security.dom_sid("S-1-5-21-3874029520-2253553080-878871061")
	
	
	try:
		conn = psycopg2.connect("dbname='lportal' user='postgres' host='localhost' password='Qwertyu*'")
	except:
		print "I am unable to connect to the database."
	
	try:
		cur = conn.cursor()
		cur.execute("select parent_id from dir where id=%s", (id, ))
	except:
		print "I can't select parent_id"
	
	conn.commit()
	parentId = cur.fetchone()[0];
	print("parentId:")
	print(parentId)
	cur.close()
	
	getValFromXattr = "select val from xattr WHERE name='security.NTACL' and dir_id = %s;"
	cur = conn.cursor()
	try:
		cur.execute(getValFromXattr, (parentId, ))
	except:
		print "I can't getValFromXattr"
	
	conn.commit()
	valFromXattr = cur.fetchone()[0];
	cur.close()
	conn.close();
	
	try:
		ntacl = ndr_unpack(xattr.NTACL, valFromXattr)
	except:
		print "I am unable ndr_unpack."
	
	print(ntacl)
	print('version:')
	print(ntacl.version)
	print(ntacl.info)
	#print(ntacl.info.sd)
	
	if ntacl.version == 1:
		parentSd = ntacl.info;
	else:
		parentSd = ntacl.info.sd;
	
	try:
		sddlParent = security.descriptor.as_sddl(parentSd)
		print(sddlParent)
	except Exception, e:
		print str(e)
	
	print("int(isDir) == 1")
	int(isDir) == 1
	
	try:
		if int(isDir) == 1:
			sddl_result = sddlParent.replace("D:PAI", "D:AI").replace("A;OICI;","A;OICIID;");
			print('dir - ' + sddl_result)
		else:
			sddl_result = sddlParent.replace("D:PAI", "D:AI").replace("A;OICI;","A;ID;").replace("A;OICIID;","A;ID;");
			print('file - ' + sddl_result)
	except Exception, e:
		print str(e)
	
	print("sid")
	
	# Save generated sddl to db
	sid = security.dom_sid("S-1-5-21-3874029520-2253553080-878871061")
	print(sid)
	try:
		lp = LoadParm()
		setntacl(lp, path, sddl_result, sid)
	except Exception, e:
		print str(e)
	
	print("run redis")
	r = redis.StrictRedis(host='localhost', port=6379, db=0)
	r.delete(str(parentId)+":dir");
	
	print('finish set_acl_from_root2!')

def set_acl_from_root(id,isDir):
	print('start set_acl_from_root!')
	
	#print(sys.argv[0:])
	#print(sys.argv[1:])
	
	print(id)	
	print(isDir)
	
	sid = security.dom_sid("S-1-5-21-3874029520-2253553080-878871061")
	
	
	try:
		conn = psycopg2.connect("dbname='lportal-project' user='postgres' host='localhost' password='Qwertyu*'")
	except:
		print "I am unable to connect to the database."
	
	getValFromXattr = "select val from xattr WHERE name='security.NTACL' and dir_id = (select parent_id from dir where id=%s);"
	cur = conn.cursor()
	try:
		cur.execute(getValFromXattr, (id, ))
	except:
		print "I can't getValFromXattr"
	
	conn.commit()
	valFromXattr = cur.fetchone()[0];
	cur.close()
	
	try:
		ntacl = ndr_unpack(xattr.NTACL, valFromXattr)
	except:
		print "I am unable ndr_unpack."
	
	print(ntacl)
	print('version:')
	print('version:')
	print(ntacl.version)
	print(ntacl.info)
	#print(ntacl.info.sd)
	
	if ntacl.version == 1:
		parentSd = ntacl.info;
	else:
		parentSd = ntacl.info.sd;
	
	
	try:
		sddlParent = security.descriptor.as_sddl(parentSd)
		print(sddlParent)
	except Exception, e:
		 print str(e)
	
	if int(isDir) == 1:
		sddl_result = sddlParent.replace("D:PAI", "D:AI").replace("A;OICI;","A;OICIID;");
		print('dir - ' + sddl_result)
	else:
		sddl_result = sddlParent.replace("D:PAI", "D:AI").replace("A;OICI;","A;ID;").replace("A;OICIID;","A;ID;");
		print('file - ' + sddl_result)
	
	# Save generated sddl to db
	sid = security.dom_sid("S-1-5-21-3874029520-2253553080-878871061")
	
	try:
		sd_root = security.descriptor.from_sddl(sddl_result, sid)
	except Exception, e:
		 print str(e)
		 
	ntacl_root = xattr.NTACL()
	ntacl_root.version = 1
	ntacl_root.info = sd_root
	ndrpack_root = ndr_pack(ntacl_root)
	
	cur = conn.cursor()
	#updateValInXattr = "UPDATE xattr SET val=%s WHERE name='security.NTACL' and dir_id =%s;"
	
	try:
		cur.execute("DELETE from xattr where name='security.NTACL' and dir_id =%s;", (id, ))
	except:
		print "I can't updateValInXattr"
	
	updateValInXattr = "INSERT INTO xattr(dir_id, name, val) VALUES(%s, %s, %s)";
	try:
		cur.execute(updateValInXattr, (id, 'security.NTACL', psycopg2.Binary(ndrpack_root), ))
	except:
		print "I can't updateValInXattr"
	
	conn.commit()
	cur.close()
	conn.close()
	
	r = redis.StrictRedis(host='localhost', port=6379, db=0)
	r.delete(id);
	print('finish set_acl_from_root!')

def set_ntacl(dir_id,sddl):
	print('start set_ntacl!')
	
	print(dir_id)
	
	#print(sys.argv[0:])
	#print(sys.argv[1:])
	
	#sddl = "O:SYG:S-1-5-21-3874029520-2253553080-878871061-1113D:PAI(A;OICI;0x001f01ff;;;SY)(A;OICI;0x001201ff;;;S-1-5-21-3874029520-2253553080-878871061-1118)"
	print(sddl)	
	
	sddl_sub_folder = sddl.replace("D:PAI", "D:AI").replace("A;OICI","A;OICIID");
	print(sddl_sub_folder)
	
	sddl_file = sddl.replace("D:PAI", "D:AI").replace("A;OICI","A;ID");
	print(sddl_file)
	
	sid = security.dom_sid("S-1-5-21-3874029520-2253553080-878871061")
	print(str(sid))
	
	print("Generate sd")
	
	## root sd
	try:
		sd_root = security.descriptor.from_sddl(sddl, sid)
	except Exception, e:
		 print str(e)
	
	print("sd_root")
	
	ntacl_root = xattr.NTACL()
	ntacl_root.version = 1
	ntacl_root.info = sd_root
	ndrpack_root = ndr_pack(ntacl_root)
	print("ndrpack_root done")
	#print(type(ndrpack))
	
	# sub folder
	sd_subfolder = security.descriptor.from_sddl(sddl_sub_folder, sid)
	
	ntacl_subfolder = xattr.NTACL()
	ntacl_subfolder.version = 1
	ntacl_subfolder.info = sd_subfolder
	ndrpack_subfolder = ndr_pack(ntacl_subfolder)
	print("ndrpack_subfolder done")
	# file
	sd_file = security.descriptor.from_sddl(sddl_file, sid)
	
	ntacl_file = xattr.NTACL()
	ntacl_file.version = 1
	ntacl_file.info = sd_file
	ndrpack_file = ndr_pack(ntacl_file)
	print("ndrpack_file done")
	
	#print(ndrpack)
	#with open('file2.txt', 'wb') as file:
	#	file.write(ndrpack.encode("hex"))

	try:
		conn = psycopg2.connect("dbname='lportal-project' user='postgres' host='localhost' password='Qwertyu*'")
	except:
		print "I am unable to connect to the database."

	#cur = conn.cursor()
	#
	#qid=254240
	#status = "security.NTACL"
	#updateRecordStatus = "UPDATE xattr SET name=%s, val=%s WHERE id=%s;"
	#	
	#try:
	#	cur.execute(updateRecordStatus, (status, psycopg2.Binary(ndrpack), qid, ))
	#except:
	#	print "I can't updateRecordStatus"
	#
	#conn.commit()
	#cur.close()
	
	# call function
	
	qid=dir_id #1603237
	
	print("run func_update_ntacl")
	cur = conn.cursor()
	
	try:
		cur.callproc("func_update_ntacl", (qid, psycopg2.Binary(ndrpack_root), psycopg2.Binary(ndrpack_subfolder), psycopg2.Binary(ndrpack_file), ))
	except:
		print "I can't call func_update_ntacl"
	
	conn.commit()
	cur.close()
	
	print("run func_get_tree")
	cur = conn.cursor()
	
	try:
		cur.callproc("func_get_tree", (qid, ))
	except:
		print "I can't call func_get_tree"
	
	conn.commit()
		
	ids = cur.fetchone()[0];
	print("ids:")
	print(ids)
	
	cur.close()
	conn.close()
	
	print("run redis")
	r = redis.StrictRedis(host='localhost', port=6379, db=0)
	r.delete(dir_id);
	if ids is not None:
		for record in ids.split(" "):
			print(record)
			r.delete(record);
	
	print('finish set_ntacl!')

if __name__ == "__main__":
	import sys
	if int(sys.argv[1]) == 1:
		set_ntacl(sys.argv[2], sys.argv[3])
	elif int(sys.argv[1]) == 2:
		set_acl_from_root(sys.argv[2], sys.argv[3])
	elif int(sys.argv[1]) == 3:
		set_acl_from_root2(sys.argv[2], sys.argv[3], sys.argv[4])
	else:
		set_acl(sys.argv[2], sys.argv[3])
