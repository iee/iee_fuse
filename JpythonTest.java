import org.python.util.PythonInterpreter; 
import org.python.core.*; 
 
public class JpythonTest {
	
	public static void main(String[] args) {
 
		PythonInterpreter python = new PythonInterpreter();
		 
		int number1 = 10;
		int number2 = 32;
		 
		python.set("number1", new PyInteger(number1));
		python.set("number2", new PyInteger(number2));
		python.exec("number3 = number1+number2");
		PyObject number3 = python.get("number3");
		System.out.println("val : "+number3.toString());

		PythonInterpreter interp = new PythonInterpreter();
		interp.exec("import sys");
		interp.exec("sys.path.append('/usr/lib/python2.7/dist-packages/samba/dcerpc')");
		interp.exec("import t");

	}
}

