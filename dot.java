import org.python.util.PythonInterpreter; 
import org.python.core.*; 
 
public class dot {
	public static void main(String[] args) {
		PythonInterpreter python = new PythonInterpreter();
		int number1 = 10;
		int number2 = 32;
		python.set("number1", new PyInteger(number1));
		python.set("number2", new PyInteger(number2));
//		python.set("myPythonDir", new PyString("/usr/lib/python2.7/dist-packages/:/usr/local/lib/python2.7/dist-packages/"));
//         	python.set("myPythonDir", new PyString("./"));
		python.exec("number3 = number1+number2");
		PyObject number3 = python.get("number3");
		System.out.println("val : "+number3.toString());
		python.exec("import pycimport");
		python.exec("import sys");
		python.exec("sys.path.append('/usr/lib/python2.7/dist-packages')");
		python.exec("sys.path.append('/usr/local/lib/python2.7/dist-packages')");
//python.exec("import psycopg2.psycopg1");
//lp = LoadParm()
//from samba.param import LoadParm
//from samba import ntacls
		python.exec("from samba import ntacls");
		python.exec("from samba.param import LoadParm");
		python.exec("lp = LoadParm()");
		python.exec("ntacls.setntacl(lp, '/opt/smb/mnt/Проекты/p7/00-Документы/Обмен/test2', 'O:SYG:S-1-5-21-3874029520-2253553080-878871061-1113D:AI(A;OICIID;0x001f01ff;;;SY)(A;OICIID;0x001201ff;;;S-1-5-21-3874029520-2253553080-878871061-1118)', 'S-1-5-21-2212615479-2695158682-2101375467', backend=None, eadbfile=None, use_ntvfs=True, skip_invalid_chown=False, passdb=None, service=None)");
		
//		String scriptname = "t.py";
//		python.execfile(scriptname);
//		python.exec("");
//		python.exec("t.t()");
	}
}
