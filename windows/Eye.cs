using System;
using System.Diagnostics;
using System.IO;
using System.Collections.Generic;
using System.Management;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace EyeScreenSaver
{
    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            string projectDir = FindProjectDirectory();
            if (string.IsNullOrEmpty(projectDir))
            {
                MessageBox.Show("Eye — Protetor de Tela\n\nNão foi possível localizar os arquivos do Eye.\nPor favor, execute 'instalar_protetor_de_tela.bat' na pasta do projeto.", "Eye", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            string appPyPath = Path.Combine(projectDir, "app.py");
            string webPath = Path.Combine(projectDir, "web", "index.html");
            string temasPath = Path.Combine(projectDir, "Temas");

            string mode = "/s";
            if (args != null && args.Length > 0)
            {
                string firstArg = args[0].ToLower().Trim();
                if (firstArg.StartsWith("/c") || firstArg.StartsWith("-c")) mode = "/c";
                else if (firstArg.StartsWith("/p") || firstArg.StartsWith("-p")) mode = "/p";
                else if (firstArg.StartsWith("/s") || firstArg.StartsWith("-s")) mode = "/s";
            }

            // Modo de Configuração: Abre a pasta de temas no Explorer
            if (mode == "/c")
            {
                if (Directory.Exists(temasPath))
                {
                    Process.Start("explorer.exe", "\"" + temasPath + "\"");
                }
                else
                {
                    MessageBox.Show("Eye — Protetor de Tela Windows\n\nAdicione novos temas na pasta 'Temas'.", "Eye", MessageBoxButtons.OK, MessageBoxIcon.Information);
                }
                return;
            }

            // Modo de Miniatura / Prévia no diálogo do Windows
            if (mode == "/p")
            {
                return;
            }

            // Modo Screensaver (/s): sobe o servidor (câmera), abre o olho em tela cheia e FICA VIVO
            // até haver atividade do usuário. Quando este processo termina, o Windows bloqueia a
            // sessão (se "Ao reiniciar, exibir tela de logon" estiver ligado) e pede a senha.
            if (!IsServerUp() && File.Exists(appPyPath))
            {
                StartServer(projectDir, appPyPath);
                for (int i = 0; i < 40 && !IsServerUp(); i++) Thread.Sleep(200);
            }
            bool serverOk = IsServerUp();
            string targetUrl = serverOk ? "http://127.0.0.1:54321" : ("file:///" + webPath.Replace('\\', '/'));

            KillKiosk();

            Application.EnableVisualStyles();
            Form cover = new Form();
            cover.FormBorderStyle = FormBorderStyle.None;
            cover.StartPosition = FormStartPosition.Manual;
            cover.Bounds = SystemInformation.VirtualScreen;
            cover.BackColor = System.Drawing.Color.Black;
            cover.ShowInTaskbar = false;
            cover.Shown += delegate { Cursor.Hide(); };
            cover.Shown += delegate { LaunchEdge(targetUrl); };

            DateTime started = DateTime.UtcNow;
            uint baseline = 0;
            bool baselineSet = false;
            System.Windows.Forms.Timer poll = new System.Windows.Forms.Timer();
            poll.Interval = 200;
            poll.Tick += delegate
            {
                // Dá 2s de carência para o Edge abrir sem que isso conte como atividade
                if ((DateTime.UtcNow - started).TotalMilliseconds < 2000) return;
                uint now = LastInputTick();
                if (!baselineSet) { baseline = now; baselineSet = true; return; }
                if (now != baseline) { try { File.AppendAllText(Path.Combine(Path.GetTempPath(), "eye_scr.log"), DateTime.Now.ToString("HH:mm:ss") + " saiu: baseline=" + baseline + " agora=" + now + " tick=" + Environment.TickCount + Environment.NewLine); } catch { } cover.Close(); }
            };
            poll.Start();
            Application.Run(cover);
            poll.Stop();
            Cursor.Show();
            KillKiosk();
            // Protetor seguro: ao sair por atividade do usuário, bloqueia a sessão (pede a senha do Windows)
            if (IsSecureScreensaver()) LockWorkStation();
        }

        [DllImport("user32.dll")]
        static extern bool LockWorkStation();

        static bool IsSecureScreensaver()
        {
            try
            {
                using (RegistryKey k = Registry.CurrentUser.OpenSubKey(@"Control Panel\Desktop"))
                {
                    return k != null && Convert.ToString(k.GetValue("ScreenSaverIsSecure")) == "1";
                }
            }
            catch { return false; }
        }

        [StructLayout(LayoutKind.Sequential)]
        struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }

        [DllImport("user32.dll")]
        static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

        static uint LastInputTick()
        {
            LASTINPUTINFO info = new LASTINPUTINFO();
            info.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
            return GetLastInputInfo(ref info) ? info.dwTime : 0;
        }

        static bool IsServerUp()
        {
            try
            {
                using (TcpClient c = new TcpClient())
                {
                    IAsyncResult r = c.BeginConnect("127.0.0.1", 54321, null, null);
                    return r.AsyncWaitHandle.WaitOne(300) && c.Connected;
                }
            }
            catch { return false; }
        }

        static void StartServer(string projectDir, string appPyPath)
        {
            List<string> candidates = new List<string>();
            candidates.Add("pythonw");
            try
            {
                string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Programs\Python");
                if (Directory.Exists(root))
                {
                    foreach (string d in Directory.GetDirectories(root, "Python3*"))
                        candidates.Add(Path.Combine(d, "pythonw.exe"));
                }
            }
            catch { }
            candidates.Add("python");

            foreach (string exe in candidates)
            {
                try
                {
                    ProcessStartInfo psi = new ProcessStartInfo();
                    psi.FileName = exe;
                    psi.Arguments = "\"" + appPyPath + "\" --no-browser";
                    psi.WorkingDirectory = projectDir;
                    psi.WindowStyle = ProcessWindowStyle.Hidden;
                    psi.CreateNoWindow = true;
                    psi.UseShellExecute = false;
                    Process.Start(psi);
                    return;
                }
                catch { }
            }
        }

        static string FindEdge()
        {
            string[] roots = new string[] {
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData)
            };
            foreach (string r in roots)
            {
                string e = Path.Combine(r, @"Microsoft\Edge\Application\msedge.exe");
                if (File.Exists(e)) return e;
            }
            return null;
        }

        static void LaunchEdge(string url)
        {
            string edge = FindEdge();
            string tempProfile = Path.Combine(Path.GetTempPath(), "EyeEdgeKioskProfile");
            try
            {
                if (edge != null)
                {
                    ProcessStartInfo psi = new ProcessStartInfo();
                    psi.FileName = edge;
                    psi.Arguments = string.Format("--user-data-dir=\"{0}\" --no-first-run --no-default-browser-check --kiosk \"{1}\" --edge-kiosk-type=fullscreen", tempProfile, url);
                    Process.Start(psi);
                    return;
                }
                Process.Start(url);
            }
            catch { }
        }

        static void KillKiosk()
        {
            try
            {
                using (ManagementObjectSearcher s = new ManagementObjectSearcher(
                    "SELECT ProcessId FROM Win32_Process WHERE Name='msedge.exe' AND CommandLine LIKE '%EyeEdgeKioskProfile%'"))
                {
                    foreach (ManagementObject o in s.Get())
                    {
                        try { Process.GetProcessById((int)(uint)o["ProcessId"]).Kill(); } catch { }
                    }
                }
            }
            catch { }
        }

        static string FindProjectDirectory()
        {
            // 1. Verifica se está rodando da própria pasta do projeto
            string currentExeDir = AppDomain.CurrentDomain.BaseDirectory;
            if (File.Exists(Path.Combine(currentExeDir, "app.py")))
            {
                return currentExeDir;
            }

            // 2. Verifica a chave de registro gravada pelo instalador
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Software\EyeScreensaver"))
                {
                    if (key != null)
                    {
                        string regPath = key.GetValue("InstallPath") as string;
                        if (!string.IsNullOrEmpty(regPath) && File.Exists(Path.Combine(regPath, "app.py")))
                        {
                            return regPath;
                        }
                    }
                }
            }
            catch { }

            // 3. Fallback para o caminho local conhecido do projeto
            string fallback = @"c:\Users\bruno_soares47\PROTETOR DE TELA\Eyes_for_compiuter";
            if (File.Exists(Path.Combine(fallback, "app.py")))
            {
                return fallback;
            }

            return null;
        }
    }
}
