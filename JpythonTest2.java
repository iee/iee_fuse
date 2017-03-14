import java.io.BufferedReader;
import java.io.InputStreamReader;

public class JpythonTest2 {

	public static void main(String[] args) {
		try {

		System.out.println("Start");
		
			//long folderId = 1603237;
			//String smbPermsStr = "O:SYG:S-1-5-21-3874029520-2253553080-878871061-1113D:PAI(A;OICI;0x001f01ff;;;SY)(A;OICI;0x001201ff;;;S-1-5-21-3874029520-2253553080-878871061-1118)";
			
			String func = "3";
			String folderId="2158426";
			String isDir="1";
			String path = "/opt/smb/mnt/Проекты/p7/00-Документы/Обмен/test9";
			//String cmd = String.format("%s %s %s %s", "python", "/home/proguser/pgfuse/smb_util.py", func, folderId, String.format("%s", smbPermsStr));
			//Process p = Runtime.getRuntime().exec(cmd);

			//String cmd = String.format("%s %s %s %s", "python", "/home/proguser/pgfuse/smb_util.py", "" + folderId, String.format("%s", smbPermsStr));
			//Process p = Runtime.getRuntime().exec(cmd);
			
			//ProcessBuilder pb = new ProcessBuilder("sudo","su","python", "/home/proguser/pgfuse/smb_util.py", func , folderId, isDir, String.format("\"%s\"", path));
			//Process p = pb.start();

			String cmd = String.format("%s %s %s %s %s %s", "sudo python", "/home/proguser/pgfuse/smb_util.py", func , folderId, isDir, String.format("\"%s\"", path));
			
			System.out.println(cmd);

//			Process p = Runtime.getRuntime().exec(cmd);
			Process p = Runtime.getRuntime().exec(new String[]{"bash", "-c", cmd});
			
			BufferedReader in = new BufferedReader(new InputStreamReader(
					p.getInputStream()));
			
			String line = "";
			while( ( line = in.readLine()) != null) {
		       System.out.println(line);
		    }
			
			in.close();
//			
//			int ret = new Integer(in.readLine()).intValue();
			
//			System.out.println("value is : " + ret);
			
		} catch (Exception e) {
			e.printStackTrace();
            throw new RuntimeException(e);
		}
	}
}
