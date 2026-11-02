using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;
[assembly: AssemblyTitle("Wallpaper Upload")]
[assembly: AssemblyCompany("Labtoso")]
[assembly: AssemblyProduct("Wallpaper Upload")]
[assembly: AssemblyCopyright("Labtoso")]
[assembly: AssemblyVersion("1.0.0.0")]
internal static class Launcher {
    [STAThread] private static void Main() {
        try {
            string root = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
            string script = Path.Combine(root, "uploader", "Wallpaper-Upload.ps1");
            if (!File.Exists(script)) throw new FileNotFoundException("Bitte die EXE im Wallpaper-Ordner lassen. Der Unterordner uploader wird benötigt.");
            string shell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
            ProcessStartInfo start = new ProcessStartInfo(shell, "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + "\"");
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            start.WorkingDirectory = root;
            Process.Start(start);
        } catch (Exception error) { MessageBox.Show(error.Message, "Wallpaper Upload", MessageBoxButtons.OK, MessageBoxIcon.Error); }
    }
}
