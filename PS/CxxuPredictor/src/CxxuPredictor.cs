using System;
using System.Collections.Generic;
using System.Management.Automation;
using System.Management.Automation.Language;
using System.Management.Automation.Runspaces;
using System.Management.Automation.Subsystem.Prediction;
using System.Threading;

namespace CxxuPredictor
{
    // 命令名前缀 predictor:只处理“裸命令名 token”(如 get-child),
    // 参数/路径/git 交给 CompletionPredictor,不重叠。
    // 缓存表 import 时建一次(约百毫秒,走 OnIdle 延迟加载,用户无感);
    // 每次按键只是内存前缀过滤,微秒级,远小于 20ms 超时。
    public class CxxuCommandPredictor : ICommandPredictor
    {
        private readonly Guid _guid;
        private readonly List<string> _commands;

        internal CxxuCommandPredictor(string guid)
        {
            _guid = new Guid(guid);
            _commands = LoadCommandNames();
        }

        public Guid Id => _guid;
        public string Name => "CxxuCommand";
        public string Description => "Prefix match on cached command names (command-name position only).";

        public SuggestionPackage GetSuggestion(PredictionClient client, PredictionContext context, CancellationToken cancellationToken)
        {
            Token token = context?.TokenAtCursor;
            if (token is null || !token.TokenFlags.HasFlag(TokenFlags.CommandName))
            {
                return default;
            }
            string prefix = token.Text;
            if (string.IsNullOrEmpty(prefix))
            {
                return default;
            }
            List<string> matches = FilterCommands(_commands, prefix, 30);
            if (matches.Count == 0 || cancellationToken.IsCancellationRequested)
            {
                return default;
            }
            List<PredictiveSuggestion> list = new List<PredictiveSuggestion>(matches.Count);
            foreach (string m in matches)
            {
                list.Add(new PredictiveSuggestion(m));
            }
            return new SuggestionPackage(list);
        }

        // 纯函数,便于 headless 反射测试;只读共享表,多线程并发读安全。
        internal static List<string> FilterCommands(List<string> commands, string prefix, int max)
        {
            List<string> result = new List<string>();
            if (commands is null || string.IsNullOrEmpty(prefix) || max <= 0)
            {
                return result;
            }
            foreach (string c in commands)
            {
                if (result.Count >= max)
                {
                    break;
                }
                if (c.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) &&
                    !string.Equals(c, prefix, StringComparison.OrdinalIgnoreCase))
                {
                    result.Add(c);
                }
            }
            return result;
        }

        private static List<string> LoadCommandNames()
        {
            List<string> names = new List<string>();
            try
            {
                using (System.Management.Automation.PowerShell ps =
                    System.Management.Automation.PowerShell.Create(RunspaceMode.CurrentRunspace))
                {
                    ps.AddScript("Get-Command -CommandType Function,Cmdlet,Alias | Select-Object -ExpandProperty Name -Unique | Sort-Object");
                    foreach (PSObject o in ps.Invoke())
                    {
                        if (o?.BaseObject is string s && s.Length > 0)
                        {
                            names.Add(s);
                        }
                    }
                }
            }
            catch
            {
                // 建表失败就空表运行(静默降级),不炸 import。
            }
            return names;
        }

        public bool CanAcceptFeedback(PredictionClient client, PredictorFeedbackKind feedback) => false;
        public void OnSuggestionDisplayed(PredictionClient client, uint session, int countOrIndex) { }
        public void OnSuggestionAccepted(PredictionClient client, uint session, string acceptedSuggestion) { }
        public void OnCommandLineAccepted(PredictionClient client, IReadOnlyList<string> history) { }
        public void OnCommandLineExecuted(PredictionClient client, string commandLine, bool success) { }
    }
}
