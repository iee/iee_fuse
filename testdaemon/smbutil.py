#! /usr/bin/python2.7
# -*- coding: utf-8 -*-
from __future__ import unicode_literals

import os
import sys
import codecs
import psycopg2
import redis
import re
#from psycopg2cffi import compat
#compat.register()
from samba.param import LoadParm
from samba.ntacls import setntacl, getntacl, XattrBackendError
import samba.xattr_native, samba.xattr_tdb, samba.posix_eadb
from samba.dcerpc import security, xattr, idmap
from samba.ndr import ndr_pack, ndr_unpack
from samba.samba3 import smbd

def get_domen_sid(sddl):
    pat = "S\-[0-9]\-[0-9]\-[0-9]{2}\-[0-9]{10}\-[0-9]{10}\-[0-9]{9}"
    result = re.findall(pat, sddl)
    print result[0]
    return result[0]

def set_acl(path, sddl):

    print('start set_acl!')
    print(path)
    print(sddl)
    sd_dom = get_domen_sid(sddl)
    sid = security.dom_sid(sd_dom)
    #sid = security.dom_sid("S-1-5-21-3874029520-2253553080-878871061")
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
    
    #sid = security.dom_sid("S-1-5-21-3874029520-2253553080-878871061")
    
    
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
    
    # Save generated sddl to db
    sd_dom = get_domen_sid(sddlParent)
    sid = security.dom_sid(sd_dom)
    #sid = security.dom_sid("S-1-5-21-3874029520-2253553080-878871061")
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
    return

def set_acl_from_root(id,isDir):
    print('start set_acl_from_root!')
    
    #print(sys.argv[0:])
    #print(sys.argv[1:])
    
    print(id)    
    print(isDir)
    
    #sid = security.dom_sid("S-1-5-21-3874029520-2253553080-878871061")
    
    
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
    sd_dom = get_domen_sid(sddlParent)
    sid = security.dom_sid(sd_dom)
    #sid = security.dom_sid("S-1-5-21-3874029520-2253553080-878871061")
    
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
    return


def get_sid(name):
    r = redis.StrictRedis(host='localhost', port=6379, db=0)
    key = "namead:"+name
    sid = r.get(key)
    print("REDIS:")
    print(sid)
    if name == "система":
        sid = "SY"
    elif sid == None:
        try:
            conn = psycopg2.connect("dbname='portal' user='postgres' host='localhost' password='Qwertyu*'")
        except:
            print "I am unable to connect to the database."
        cur = conn.cursor()

        try:
            cur.execute("SELECT u.sid as sid FROM user_ u WHERE u.screenname=%s UNION SELECT g.sid as sid FROM usergroup g WHERE g.name=%s;", (name,name, ))
        except:
            print "I can't get SID"

        conn.commit()
        sid = cur.fetchone()[0];
        cur.close()
        conn.close()
        print("run redis")
        #r = redis.StrictRedis(host='localhost', port=6379, db=0)
        #key = "namead:"+name
        r.append(key,sid);
        print(sid)

    return sid

def make_sddl(parm):
    inh = parm["Inherited"]
    o = parm["Owner"]
    g = parm["Group"]
    if inh == "True":
        d = "AI"
        a = "OICIID"
    else:
        d = "PAI"
        a = "OICI"

    sddl = "O:"+get_sid(o)+"G:"+get_sid(g)+"D:"+d
    for acl in parm["ACL"]:
        right = acl["Right"]
        if right == "FULL":
            r = "0x001f01ff"
        elif right == "READ":
            r = "0x001200a9"
        else:
            r = "0x001201ff"
        sddl = sddl + "(A;"+a+";"+r+";;;"+get_sid(acl["Name"])+")"

    print(sddl)
    return sddl

def set_sd(parm):
    sddl = make_sddl(parm)
    id = parm["FolderID"]
    sd_dom = get_domen_sid(sddl)
    sid = security.dom_sid(sd_dom)
    #sid = security.dom_sid("S-1-5-21-3874029520-2253553080-878871061")
    print("Generate sd")
    try:
        sd = security.descriptor.from_sddl(sddl, sid)
    except Exception, e:
         print str(e)
    ntacl_sd = xattr.NTACL()
    ntacl_sd.version = 1
    ntacl_sd.info = sd
    ndrpack_sd = ndr_pack(ntacl_sd)
    print("ndrpack_sd done")

    try:
        conn = psycopg2.connect("dbname='portal' user='postgres' host='localhost' password='Qwertyu*'")
    except:
        print "I am unable to connect to the database."

    cur = conn.cursor()
    print(id)
    try:
        cur.callproc("func_insupd_ntacl", (id, psycopg2.Binary(ndrpack_sd), ))
    except:
        print "I can't call func_insupd_ntacl"
    
    conn.commit()
    cur.close()
    conn.close()
    r = redis.StrictRedis(host='localhost', port=6379, db=0)
    r.delete(id);
    print('finish set_sd!')

def get_sddl_from_paren(id):
    print('run get_sddl_from_paren')
    print('id:')
    print(id)
    try:
        conn = psycopg2.connect("dbname='portal' user='postgres' host='localhost' password='Qwertyu*'")
    except:
        print "I am unable to connect to the database."
    strgetval = "SELECT val FROM xattr WHERE name='security.NTACL' AND dir_id = (SELECT parent_id FROM dir WHERE id=%s);"
    cur = conn.cursor()
    try:
        cur.execute(strgetval, (id, ))
    except:
        print "I can't getParentValFromXattr"

    conn.commit()
    val = cur.fetchone()[0];
    cur.close()

    try:
        ntacl = ndr_unpack(xattr.NTACL, val)
    except:
        print "I am unable ndr_unpack."
    if ntacl.version == 1:
        parentSd = ntacl.info;
    else:
        parentSd = ntacl.info.sd;

    try:
        sddl = security.descriptor.as_sddl(parentSd)
    except Exception, e:
        print str(e)
    
    print(sddl)
    return(sddl)

def set_sd_from_parent(parm):
    try:
        conn = psycopg2.connect("dbname='portal' user='postgres' host='localhost' password='Qwertyu*'")
    except:
        print "I am unable to connect to the database."
    id = parm["ItemID"]
    parentSddl = get_sddl_from_paren(id)
    if parm["Directory"] == "True":
       sddl = parentSddl.replace("D:PAI", "D:AI").replace("A;OICI;","A;OICIID;");
       print("dir - " + sddl)
    else:
       sddl = parentSddl.replace("D:PAI", "D:AI").replace("A;OICI;","A;ID;").replace("A;OICIID;","A;ID;");
       print("file - " + sddl)
    print("Generate sd")
    sd_dom = get_domen_sid(parentSddl)
    sid = security.dom_sid(sd_dom)
    #sid = security.dom_sid("S-1-5-21-3874029520-2253553080-878871061")
    try:
       sd = security.descriptor.from_sddl(sddl, sid)
    except Exception, e:
       print str(e)
    ntacl_sd = xattr.NTACL()
    ntacl_sd.version = 1
    ntacl_sd.info = sd
    ndrpack_sd = ndr_pack(ntacl_sd)
    print("ndrpack_sd done")
    cur = conn.cursor()
    print(id)
    try:
        cur.callproc("func_insupd_ntacl", (id, psycopg2.Binary(ndrpack_sd), ))
    except:
        print "I can't call func_insupd_ntacl"
    conn.commit()
    cur.close()
    conn.close()
    r = redis.StrictRedis(host='localhost', port=6379, db=0)
    r.delete(id);
    print('finish set_sd_from_parent!')
    return sddl;

def set_ntacl(dir_id,sddl):
    print('start set_ntacl!')
    print(dir_id)
    print(sddl)    
    
    sddl_sub_folder = sddl.replace("D:PAI", "D:AI").replace("A;OICI","A;OICIID");
    print(sddl_sub_folder)
    
    sddl_file = sddl.replace("D:PAI", "D:AI").replace("A;OICI","A;ID");
    print(sddl_file)
    
    sd_dom = get_domen_sid(sddl)
    sid = security.dom_sid(sd_dom)
    #sid = security.dom_sid("S-1-5-21-3874029520-2253553080-878871061")
    print(str(sid))
    
    print("Generate sd")
    
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

    try:
        conn = psycopg2.connect("dbname='portal' user='postgres' host='localhost' password='Qwertyu*'")
    except:
        print "I am unable to connect to the database."

    qid=dir_id #1603237
    
    print("run func_update_child_ntacl")
    cur = conn.cursor()
    
    try:
        cur.callproc("func_update_child_ntacl", (qid, psycopg2.Binary(ndrpack_subfolder), psycopg2.Binary(ndrpack_file), ))
    except:
        print "I can't call func_update_child_ntacl"
    
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

def recalcExistingFolder(parm):
    print('start recalcExistingFolder!')
    project_id = parm["id"]
    try:
        conn = psycopg2.connect("dbname='portal' user='postgres' host='localhost' password='Qwertyu*'")
    except:
        print "I am unable to connect to the database."
    
    print("run func_get_sddl_by_id")
    cur = conn.cursor()
    try:
        cur.callproc("func_get_sddl_by_id", (project_id, ))
    except:
        print "I can't call func_get_sddl_by_id"
    conn.commit()
    sddl = cur.fetchone()[0];
    print("sddl:")
    print(sddl)
    cur.close()
    print("finish func_get_sddl_by_id")
    
    if sddl is None:
        parm["Directory"]="True";
        parm["ItemID"]=project_id;
        folderSddl = set_sd_from_parent(parm);
        parm["FolderID"]=project_id
        parm["sddl"]=folderSddl
        set_tree_ntacl(parm);
    
    cur = conn.cursor()
    print('project_id:')
    print(project_id)
    try:
        cur.callproc("func_get_tree_dir_sddl", (project_id, ))
    except:
        print "I can't call func_get_tree_dir_sddl"
    conn.commit()
    rows = cur.fetchall()
    for row in rows:
        id = row[0];
        sddl = row[1];
        parm["FolderID"]=id
        parm["sddl"]=sddl
        set_tree_ntacl(parm);

    cur.close()
    conn.close()

def set_tree_ntacl(parm):
    print('start set_tree_ntacl!')
    #sddl = make_sddl(parm)
    id = parm["FolderID"]
    sddl = parm["sddl"]
    print(sddl)    
    
    sddl_sub_folder = sddl.replace("D:PAI", "D:AI").replace("A;OICI","A;OICIID");
    print(sddl_sub_folder)
    
    sddl_file = sddl.replace("D:PAI", "D:AI").replace("A;OICI","A;ID");
    print(sddl_file)
    
    sd_dom = get_domen_sid(sddl)
    sid = security.dom_sid(sd_dom)
    #sid = security.dom_sid("S-1-5-21-3874029520-2253553080-878871061")
    print(str(sid))
    
    print("Generate sd")

    # root sd
    try:
        sd_root = security.descriptor.from_sddl(sddl, sid)
    except Exception, e:
        print str(e)
    
    ntacl_root = xattr.NTACL()
    ntacl_root.version = 1
    ntacl_root.info = sd_root
    ndrpack_root = ndr_pack(ntacl_root)
    print("ndrpack_root done")

    # sub folder
    try:
        sd_subfolder = security.descriptor.from_sddl(sddl_sub_folder, sid)
    except Exception, e:
        print str(e)
    
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

    try:
        conn = psycopg2.connect("dbname='portal' user='postgres' host='localhost' password='Qwertyu*'")
    except:
        print "I am unable to connect to the database."

    print("run func_update_ntacl")
    cur = conn.cursor()
    
    try:
        cur.callproc("func_update_ntacl", (id, psycopg2.Binary(ndrpack_root), psycopg2.Binary(ndrpack_subfolder), psycopg2.Binary(ndrpack_file), ))
    except:
        print "I can't call func_update_ntacl"
    
    conn.commit()
    cur.close()
    
    print("run func_get_tree")
    cur = conn.cursor()
    
    try:
        cur.callproc("func_get_tree", (id, ))
    except:
        print "I can't call func_get_tree"
    
    conn.commit()
        
    ids = cur.fetchone()[0];
    print(ids)
    
    cur.close()
    conn.close()
    
    print("run redis")
    r = redis.StrictRedis(host='localhost', port=6379, db=0)
    r.delete(id);
    if ids is not None:
        for record in ids.split(" "):
            print(record)
            r.delete(record);
    
    print('finish set_tree_ntacl!')
