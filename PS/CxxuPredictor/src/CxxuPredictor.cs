using System;
using System.Collections.Generic;
using System.Management.Automation;
using System.Management.Automation.Language;
using System.Management.Automation.Runspaces;
using System.Management.Automation.Subsystem.Prediction;
using System.Threading;

namespace CxxuPredictor
{
    // 命令名 predictor:VSCode QuickOpen 式模糊 + 严格通配符,都只处理“裸命令名 token”,
    // 含通配符(*/?/[],如 get-*ive)走 WildcardPattern 精确语义;其余走模糊(空格多片段 AND 仅 API 层);
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
        public string Description => "Fuzzy + strict wildcard match on cached command names (command-name position only).";

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
            // 含通配符走严格语义(如 get-*ive 精确首尾);裸 * 不放水;残缺括号异常兜底,线程永不抛
            if (WildcardPattern.ContainsWildcardCharacters(prefix))
            {
                try
                {
                    if (prefix.Replace("*", string.Empty).Replace("?", string.Empty).Length == 0)
                    {
                        return result;
                    }
                    WildcardPattern pattern = new WildcardPattern(prefix, WildcardOptions.IgnoreCase);
                    foreach (string c in commands)
                    {
                        if (result.Count >= max)
                        {
                            break;
                        }
                        if (string.Equals(c, prefix, StringComparison.OrdinalIgnoreCase))
                        {
                            continue;
                        }
                        if (pattern.IsMatch(c))
                        {
                            result.Add(c);
                        }
                    }
                }
                catch
                {
                    result.Clear();
                }
                return result;
            }
            // 模糊:空格切多片段,全中才算(AND;活体里空格分词到不了这,见文档)
            string query = prefix;
            string[] fragments = query.Split(new char[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
            if (fragments.Length == 0)
            {
                return result;
            }
            List<KeyValuePair<string, int>> scored = new List<KeyValuePair<string, int>>();
            foreach (string c in commands)
            {
                if (string.Equals(c, prefix, StringComparison.OrdinalIgnoreCase))
                {
                    continue; // 自匹配排除:全名照打不提示自己
                }
                int total = 0;
                bool ok = true;
                foreach (string f in fragments)
                {
                    int s = ScoreFuzzy(c, f);
                    if (s <= 0)
                    {
                        ok = false;
                        break;
                    }
                    total += s;
                }
                if (ok)
                {
                    scored.Add(new KeyValuePair<string, int>(c, total));
                }
            }
            scored.Sort((a, b) =>
            {
                int d = b.Value.CompareTo(a.Value);
                if (d != 0)
                {
                    return d;
                }
                d = a.Key.Length.CompareTo(b.Key.Length);
                if (d != 0)
                {
                    return d;
                }
                return string.Compare(a.Key, b.Key, StringComparison.OrdinalIgnoreCase);
            });
            for (int i = 0; i < scored.Count && result.Count < max; i++)
            {
                result.Add(scored[i].Key);
            }
            return result;
        }

        // 子序列模糊打分(大小写不敏感):命中+1,词边界(+2:-/首字母/驼峰)、连击(+2)、间隔扣分、起始越晚越亏
        internal static int ScoreFuzzy(string target, string fragment)
        {
            int score = 0;
            int pos = 0;
            int prev = -1;
            int first = -1;
            for (int i = 0; i < fragment.Length; i++)
            {
                char q = char.ToLowerInvariant(fragment[i]);
                int found = -1;
                for (int j = pos; j < target.Length; j++)
                {
                    if (char.ToLowerInvariant(target[j]) == q)
                    {
                        found = j;
                        break;
                    }
                }
                if (found < 0)
                {
                    return 0;
                }
                if (first < 0)
                {
                    first = found;
                }
                score += 1;
                if (found == 0 || target[found - 1] == '-' || IsCamelBoundary(target, found))
                {
                    score += 2;
                }
                else if (found == prev + 1)
                {
                    score += 2;
                }
                else if (prev >= 0)
                {
                    score -= (found - prev - 1);
                }
                prev = found;
                pos = found + 1;
            }
            score -= first;
            return score <= 0 ? 1 : score; // 命中即正分,多片段 AND 可累加;排序沉底,不污染头部
        }

        internal static bool IsCamelBoundary(string target, int pos)
        {
            return pos > 0 && char.IsLower(target[pos - 1]) && char.IsUpper(target[pos]);
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

        // Tab 侧公开入口:独立缓存表(与 predictor 实例表互不干扰,本进程首次调用时建表);
        // 给 TabExpansion2 包装调用,纯读共享表,并发安全,失败返回空数组永不抛。
        private static readonly object _tabLock = new object();
        private static List<string> _tabCommands;
        public static string[] CompleteCommand(string word, int maxResults)
        {
            try
            {
                if (string.IsNullOrEmpty(word) || maxResults <= 0)
                {
                    return Array.Empty<string>();
                }
                List<string> table = _tabCommands;
                if (table is null)
                {
                    lock (_tabLock)
                    {
                        if (_tabCommands is null)
                        {
                            _tabCommands = LoadCommandNames();
                        }
                        table = _tabCommands;
                    }
                }
                return FilterCommands(table, word, maxResults).ToArray();
            }
            catch
            {
                return Array.Empty<string>();
            }
        }

        public bool CanAcceptFeedback(PredictionClient client, PredictorFeedbackKind feedback) => false;        public void OnSuggestionDisplayed(PredictionClient client, uint session, int countOrIndex) { }
        public void OnSuggestionAccepted(PredictionClient client, uint session, string acceptedSuggestion) { }
        public void OnCommandLineAccepted(PredictionClient client, IReadOnlyList<string> history) { }
        public void OnCommandLineExecuted(PredictionClient client, string commandLine, bool success) { }
    }
}
