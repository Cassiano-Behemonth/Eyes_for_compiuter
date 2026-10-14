using System;
using System.Diagnostics;
using System.IO;
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

            // Modo Screensaver (/s) ou Execução Normal: Inicia o servidor Python com OpenCV se não estiver rodando
            bool pythonStarted = false;
            if (File.Exists(appPyPath))
            {
                try
                {
                    ProcessStartInfo psi = new ProcessStartInfo();
                    psi.FileName = "pythonw";
                    psi.Arguments = "\"" + appPyPath + "\" --no-browser";
                    psi.WorkingDirectory = projectDir;
                    psi.WindowStyle = ProcessWindowStyle.Hidden;
                    psi.CreateNoWindow = true;
                    Process.Start(psi);
                    pythonStarted = true;
                }
                catch
                {
                    try
                    {
                        ProcessStartInfo psi = new ProcessStartInfo();
                        psi.FileName = "python";
                        psi.Arguments = "\"" + appPyPath + "\" --no-browser";
                        psi.WorkingDirectory = projectDir;
                        psi.WindowStyle = ProcessWindowStyle.Hidden;
                        psi.CreateNoWindow = true;
                        Process.Start(psi);
                        pythonStarted = true;
                    }
                    catch { }
                }

                if (pythonStarted)
                {
                    Thread.Sleep(1200); // Aguarda o servidor HTTP e câmera iniciarem
                }
            }

            // Procura o executável do Microsoft Edge
            string edge = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), @"Microsoft\Edge\Application\msedge.exe");
            if (!File.Exists(edge))
            {
                edge = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"Microsoft\Edge\Application\msedge.exe");
            }
            if (!File.Exists(edge))
            {
                edge = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Microsoft\Edge\Application\msedge.exe");
            }

            string targetUrl = pythonStarted ? "http://127.0.0.1:54321" : ("file:///" + webPath.Replace('\\', '/'));
            string tempProfile = Path.Combine(Path.GetTempPath(), "EyeEdgeKioskProfile");

            if (File.Exists(edge))
            {
                try
                {
                    ProcessStartInfo edgePsi = new ProcessStartInfo();
                    edgePsi.FileName = edge;
                    edgePsi.Arguments = string.Format("--user-data-dir=\"{0}\" --no-first-run --no-default-browser-check --app=\"{1}\" --start-fullscreen", tempProfile, targetUrl);
                    Process.Start(edgePsi);
                    return;
                }
                catch { }
            }

            // Fallback para o navegador padrão
            Process.Start(targetUrl);
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
