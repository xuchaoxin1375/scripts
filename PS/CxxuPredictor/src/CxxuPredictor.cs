using System;
using System.Collections.Generic;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Language;
using System.Management.Automation.Subsystem.Prediction;
using System.Threading;

namespace CxxuPredictor
{
    // 命令表条目:名字 + 指向它的别名(小写比较)+ 使用频率权重(来自 PSReadLine 历史)。
    internal sealed class CommandEntry
    {
        public string Name;
        public List<string> Aliases;
        public int Weight;
    }

    // 命令表:条目、非别名名字集合(用于“打全名不再提示”)、以及目标反查用的字典。
    internal sealed class CommandTable
    {
        public List<CommandEntry> Commands;
        public HashSet<string> RealNames;
        public Dictionary<string, CommandEntry> ByName;
    }

    // 命令名 predictor:分层模糊匹配,只处理“裸命令名 token”:
    //   优先级 0:别名精确命中(ls → Get-ChildItem)
    //   优先级 1:完整前缀(get-chi → Get-ChildItem)
    //   优先级 2:词边界子序列/首字母缩写(gci → Get-ChildItem, chitem → Get-ChildItem)
    //   优先级 3:从词边界起的连续片段
    //   优先级 4:一般子序列(仅长查询且跨度收敛,避免单字母灌榜)
    // 同层内按“历史使用频率 + 匹配得分”排序,最后按长度与字母序稳定。
    // 含通配符(*/?/[])走 WildcardPattern 严格语义,不做模糊。
    public class CxxuCommandPredictor : ICommandPredictor
    {
        // ListView 一屏显示约 10 行(历史占前几行),可上下滚动;给足候选,不做层级裁剪。
        private const int PredictorMaxResults = 15;

        private readonly Guid _guid;
        private readonly CommandTable _table;

        internal CxxuCommandPredictor(string guid)
        {
            _guid = new Guid(guid);
            _table = LoadCommands();
        }

        public Guid Id => _guid;
        public string Name => "CxxuCommand";
        public string Description => "Tiered fuzzy and strict wildcard match on cached command names (command-name position only).";

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
            List<string> matches = FilterCommands(_table, prefix, PredictorMaxResults);
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
        internal static List<string> FilterCommands(CommandTable table, string query, int max)
        {
            List<string> result = new List<string>();
            if (table is null || table.Commands is null || string.IsNullOrEmpty(query) || max <= 0)
            {
                return result;
            }
            if (WildcardPattern.ContainsWildcardCharacters(query))
            {
                return FilterWildcard(table, query, max);
            }
            string[] fragments = query.Split(new char[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
            if (fragments.Length == 0)
            {
                return result;
            }
            // 打全名(非别名)时不再提示更长的名字:参数由 CompletionPredictor 负责
            if (fragments.Length == 1 && query.Length >= 3 && table.RealNames.Contains(query))
            {
                return result;
            }

            List<Candidate> scored = new List<Candidate>();
            foreach (CommandEntry entry in table.Commands)
            {
                if (fragments.Length == 1 && string.Equals(entry.Name, query, StringComparison.OrdinalIgnoreCase))
                {
                    continue; // 自匹配排除:全名照打不提示自己
                }
                // 别名精确命中优先于文本匹配:ls/ps 与目标名没有共同子序列,
                // 必须先判定,否则到不了排序阶段(打 ls 提示 Get-ChildItem)。
                bool aliasExact = false;
                if (fragments.Length == 1 && entry.Aliases != null)
                {
                    for (int i = 0; i < entry.Aliases.Count; i++)
                    {
                        if (string.Equals(entry.Aliases[i], query, StringComparison.OrdinalIgnoreCase))
                        {
                            aliasExact = true;
                            break;
                        }
                    }
                }
                int tier;
                int score;
                if (aliasExact)
                {
                    tier = 0;
                    score = 400;
                }
                else if (!MatchAll(entry.Name, fragments, out tier, out score))
                {
                    continue;
                }
                scored.Add(new Candidate(entry.Name, tier, score, entry.Weight));
            }
            scored.Sort(CompareCandidates);
            for (int i = 0; i < scored.Count && result.Count < max; i++)
            {
                result.Add(scored[i].Name);
            }
            return result;
        }

        private struct Candidate
        {
            public string Name;
            public int Tier;
            public int Score;
            public int Weight;

            public Candidate(string name, int tier, int score, int weight)
            {
                Name = name;
                Tier = tier;
                Score = score;
                Weight = weight;
            }
        }

        private static int CompareCandidates(Candidate a, Candidate b)
        {
            int d = a.Tier.CompareTo(b.Tier);
            if (d != 0)
            {
                return d;
            }
            // 同层内先比匹配质量,再比历史频率,避免高频但劣质的匹配压过好匹配
            d = b.Score.CompareTo(a.Score);
            if (d != 0)
            {
                return d;
            }
            d = b.Weight.CompareTo(a.Weight);
            if (d != 0)
            {
                return d;
            }
            d = a.Name.Length.CompareTo(b.Name.Length);
            if (d != 0)
            {
                return d;
            }
            return string.Compare(a.Name, b.Name, StringComparison.OrdinalIgnoreCase);
        }

        // 多片段 AND:每段都要命中,整体层级取最差的一段,得分累加。
        private static bool MatchAll(string name, string[] fragments, out int tier, out int score)
        {
            tier = 0;
            score = 0;
            for (int i = 0; i < fragments.Length; i++)
            {
                int t;
                int s;
                if (!MatchOne(name, fragments[i], out t, out s))
                {
                    return false;
                }
                if (t > tier)
                {
                    tier = t;
                }
                score += s;
            }
            return true;
        }

        private static bool MatchOne(string name, string frag, out int tier, out int score)
        {
            tier = 0;
            score = 0;
            if (string.IsNullOrEmpty(frag) || frag.Length > name.Length)
            {
                return false;
            }

            // 层级 1:完整前缀(同层内交给历史频率与长度决定先后)
            if (name.StartsWith(frag, StringComparison.OrdinalIgnoreCase))
            {
                tier = 1;
                score = 220;
                return true;
            }

            // 单字符只认前缀:首字母缩写/子序列会让 x、s 这类输入灌满无关命令
            if (frag.Length == 1)
            {
                return false;
            }

            // 层级 2:词边界子序列/首字母缩写(gci → Get-ChildItem,不要求连续)
            int first;
            int boundaryHits;
            if (BoundarySubsequence(name, frag, out first, out boundaryHits))
            {
                tier = 2;
                score = 160 + boundaryHits * 4 - first;
                return true;
            }

            // 层级 3:从词边界开始的连续片段(chitem → Get-ChildItem,get-chi 之外的连写)
            int index = name.IndexOf(frag, StringComparison.OrdinalIgnoreCase);
            while (index >= 0)
            {
                if (IsBoundary(name, index))
                {
                    tier = 3;
                    score = 120 - index;
                    if (score < 1)
                    {
                        score = 1;
                    }
                    return true;
                }
                index = name.IndexOf(frag, index + 1, StringComparison.OrdinalIgnoreCase);
            }

            // 层级 4:一般子序列。不设跨度门槛——groute → Get-NetRoute 这类跨词连写必须保留;
            // 质量交给 FuzzyScore 排序,弱匹配自然沉底。
            if (frag.Length >= 2)
            {
                score = FuzzyScore(name, frag);
                if (score > 0)
                {
                    tier = 4;
                    return true;
                }
            }
            return false;
        }

        // 只允许查询字符落在词边界上,用于识别首字母缩写(gci)。
        private static bool BoundarySubsequence(string name, string frag, out int first, out int hits)
        {
            first = -1;
            hits = 0;
            int qi = 0;
            for (int i = 0; i < name.Length && qi < frag.Length; i++)
            {
                if (!IsBoundary(name, i))
                {
                    continue;
                }
                if (char.ToLowerInvariant(name[i]) != char.ToLowerInvariant(frag[qi]))
                {
                    continue;
                }
                if (first < 0)
                {
                    first = i;
                }
                qi++;
                hits++;
            }
            return qi == frag.Length;
        }

        // 一般子序列打分(大小写不敏感):命中 +2、词边界 +6、连击 +4、间隔按长度扣分,起始越晚越亏。
        // 只要求字符按序出现;散得越开分越低,用于把 Get-NetRoute 这类跨词匹配排在弱匹配前面。
        private static int FuzzyScore(string name, string frag)
        {
            int score = 0;
            int pos = 0;
            int prev = -1;
            int first = -1;
            for (int qi = 0; qi < frag.Length; qi++)
            {
                int found = -1;
                char q = char.ToLowerInvariant(frag[qi]);
                for (int j = pos; j < name.Length; j++)
                {
                    if (char.ToLowerInvariant(name[j]) == q)
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
                score += 2;
                if (IsBoundary(name, found))
                {
                    score += 6;
                }
                if (prev >= 0)
                {
                    int gap = found - prev - 1;
                    if (gap == 0)
                    {
                        score += 4;
                    }
                    else
                    {
                        score -= gap;
                    }
                }
                prev = found;
                pos = found + 1;
            }
            score -= first;
            return score <= 0 ? 1 : score;
        }

        private static bool IsBoundary(string s, int i)
        {
            if (i == 0)
            {
                return true;
            }
            char prev = s[i - 1];
            char cur = s[i];
            if (prev == '-' || prev == '_' || prev == '.' || prev == ' ')
            {
                return true;
            }
            return char.IsLower(prev) && char.IsUpper(cur);
        }

        // 通配符走严格语义(get-*ive 精确首尾);裸 * 不放水;残缺括号兜底,线程永不抛。
        private static List<string> FilterWildcard(CommandTable table, string query, int max)
        {
            List<string> result = new List<string>();
            if (query.Replace("*", string.Empty).Replace("?", string.Empty).Length == 0)
            {
                return result;
            }
            try
            {
                WildcardPattern pattern = new WildcardPattern(query, WildcardOptions.IgnoreCase);
                List<CommandEntry> hits = new List<CommandEntry>();
                foreach (CommandEntry entry in table.Commands)
                {
                    if (string.Equals(entry.Name, query, StringComparison.OrdinalIgnoreCase))
                    {
                        continue;
                    }
                    if (pattern.IsMatch(entry.Name))
                    {
                        hits.Add(entry);
                    }
                }
                hits.Sort((a, b) =>
                {
                    int d = b.Weight.CompareTo(a.Weight);
                    if (d != 0)
                    {
                        return d;
                    }
                    d = a.Name.Length.CompareTo(b.Name.Length);
                    if (d != 0)
                    {
                        return d;
                    }
                    return string.Compare(a.Name, b.Name, StringComparison.OrdinalIgnoreCase);
                });
                for (int i = 0; i < hits.Count && result.Count < max; i++)
                {
                    result.Add(hits[i].Name);
                }
            }
            catch
            {
                result.Clear();
            }
            return result;
        }

        private static CommandTable LoadCommands()
        {
            CommandTable table = new CommandTable();
            table.Commands = new List<CommandEntry>();
            table.RealNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            table.ByName = new Dictionary<string, CommandEntry>(StringComparer.OrdinalIgnoreCase);
            Dictionary<string, string> aliasDefs = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            HashSet<string> aliasNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            try
            {
                using (System.Management.Automation.PowerShell ps =
                    System.Management.Automation.PowerShell.Create(RunspaceMode.CurrentRunspace))
                {
                    ps.AddScript("Get-Command -CommandType Function,Cmdlet,Alias | ForEach-Object { $_.Name + [char]1 + $_.CommandType + [char]1 + $_.Definition }");
                    foreach (PSObject o in ps.Invoke())
                    {
                        string line = o?.BaseObject as string;
                        if (string.IsNullOrEmpty(line))
                        {
                            continue;
                        }
                        string[] parts = line.Split('\u0001');
                        string name = parts.Length > 0 ? parts[0] : null;
                        if (string.IsNullOrEmpty(name))
                        {
                            continue;
                        }
                        string type = parts.Length > 1 ? parts[1] : null;
                        if (string.Equals(type, "Alias", StringComparison.OrdinalIgnoreCase))
                        {
                            // 未导入模块的别名可能拿不到 Definition,名字仍要进候选(gci 要能看到 gcim)
                            aliasNames.Add(name);
                            string def = parts.Length > 2 ? parts[2] : null;
                            if (!string.IsNullOrEmpty(def))
                            {
                                aliasDefs[name] = def.Trim();
                            }
                            continue;
                        }
                        if (table.ByName.ContainsKey(name))
                        {
                            continue;
                        }
                        CommandEntry entry = new CommandEntry();
                        entry.Name = name;
                        entry.Aliases = new List<string>();
                        entry.Weight = 0;
                        table.ByName[name] = entry;
                        table.Commands.Add(entry);
                        table.RealNames.Add(name);
                    }
                }
                // 别名本身也作为候选:输入 gci 时除了目标 Get-ChildItem,还能列出 gcim 这类同前缀别名
                foreach (string aliasName in aliasNames)
                {
                    if (table.ByName.ContainsKey(aliasName))
                    {
                        continue;
                    }
                    CommandEntry aliasEntry = new CommandEntry();
                    aliasEntry.Name = aliasName;
                    aliasEntry.Aliases = null;
                    aliasEntry.Weight = 0;
                    table.ByName[aliasName] = aliasEntry;
                    table.Commands.Add(aliasEntry);
                }
                // 别名归并到目标(链式别名解析到底;目标不在表内则忽略)
                Dictionary<string, string> resolvedAliases = new Dictionary<string, string>(aliasDefs.Count, StringComparer.OrdinalIgnoreCase);
                foreach (KeyValuePair<string, string> kv in aliasDefs)
                {
                    string target = kv.Value;
                    for (int hop = 0; hop < 3; hop++)
                    {
                        string next;
                        if (!aliasDefs.TryGetValue(target, out next) || string.Equals(next, target, StringComparison.OrdinalIgnoreCase))
                        {
                            break;
                        }
                        target = next;
                    }
                    resolvedAliases[kv.Key] = target;
                    CommandEntry entry;
                    if (table.ByName.TryGetValue(target, out entry))
                    {
                        entry.Aliases.Add(kv.Key);
                    }
                }
                ApplyFrecency(table, resolvedAliases);
            }
            catch
            {
                // 建表失败就空表运行(静默降级),不炸 import。
            }
            table.Commands.Sort((a, b) => string.Compare(a.Name, b.Name, StringComparison.OrdinalIgnoreCase));
            return table;
        }

        // 先猜 PSReadLine 默认历史文件(省一次 Get-PSReadLineOption 调用,约 80ms);
        // 默认文件不存在时才回退查询,兼容自定义 HistorySavePath。
        private static string GetHistoryPath()
        {
            string guess = null;
            try
            {
                if (OperatingSystem.IsWindows())
                {
                    guess = Path.Combine(
                        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                        "Microsoft", "Windows", "PowerShell", "PSReadLine", "ConsoleHost_history.txt");
                }
                else
                {
                    guess = Path.Combine(
                        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                        "powershell", "PSReadLine", "ConsoleHost_history.txt");
                }
            }
            catch
            {
                guess = null;
            }
            if (!string.IsNullOrEmpty(guess) && File.Exists(guess))
            {
                return guess;
            }
            try
            {
                using (System.Management.Automation.PowerShell ps =
                    System.Management.Automation.PowerShell.Create(RunspaceMode.CurrentRunspace))
                {
                    ps.AddScript("if (Get-Command Get-PSReadLineOption -ErrorAction SilentlyContinue) { (Get-PSReadLineOption).HistorySavePath }");
                    System.Collections.ObjectModel.Collection<PSObject> r = ps.Invoke();
                    if (r.Count > 0)
                    {
                        return r[0]?.BaseObject as string;
                    }
                }
            }
            catch
            {
            }
            return null;
        }

        // 从 PSReadLine 历史统计常用命令,作为同层排序权重;读不到就全 0,不影响功能。
        private static void ApplyFrecency(CommandTable table, Dictionary<string, string> aliasTargets)
        {
            string path = GetHistoryPath();
            if (string.IsNullOrEmpty(path) || !File.Exists(path))
            {
                return;
            }

            const int MaxLines = 5000;
            Queue<string> tail = new Queue<string>(MaxLines);
            try
            {
                foreach (string line in File.ReadLines(path))
                {
                    if (tail.Count == MaxLines)
                    {
                        tail.Dequeue();
                    }
                    tail.Enqueue(line);
                }
            }
            catch
            {
                return;
            }

            Dictionary<string, int> counts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            int total = tail.Count;
            int index = 0;
            foreach (string line in tail)
            {
                index++;
                string token = FirstToken(line);
                if (token is null)
                {
                    continue;
                }
                int add = index > total - 300 ? 4 : 1; // 最近 300 条加权
                AddCount(counts, table, token, add);
                string target;
                if (aliasTargets.TryGetValue(token, out target))
                {
                    AddCount(counts, table, target, add);
                }
            }
            foreach (KeyValuePair<string, int> kv in counts)
            {
                CommandEntry entry;
                if (table.ByName.TryGetValue(kv.Key, out entry))
                {
                    entry.Weight = Math.Min(kv.Value, 20);
                }
            }
        }

        private static void AddCount(Dictionary<string, int> counts, CommandTable table, string name, int add)
        {
            if (!table.ByName.ContainsKey(name))
            {
                return;
            }
            int old;
            counts.TryGetValue(name, out old);
            counts[name] = old + add;
        }

        private static string FirstToken(string line)
        {
            if (line is null)
            {
                return null;
            }
            string s = line.Trim();
            if (s.Length == 0 || s[0] == '#')
            {
                return null;
            }
            int end = 0;
            while (end < s.Length && !char.IsWhiteSpace(s[end]))
            {
                end++;
            }
            if (end == 0)
            {
                return null;
            }
            if (end > 64)
            {
                end = 64;
            }
            string token = s.Substring(0, end);
            if (token.Length > 1 && token[0] == '&')
            {
                token = token.Substring(1);
            }
            return token.Length == 0 ? null : token;
        }

        // Tab 侧公开入口:独立缓存表(与 predictor 实例表互不干扰,本进程首次调用时建表);
        // 给 TabExpansion2 包装调用,纯读共享表,并发安全,失败返回空数组永不抛。
        private static readonly object _tabLock = new object();
        private static CommandTable _tabTable;
        public static string[] CompleteCommand(string word, int maxResults)
        {
            try
            {
                if (string.IsNullOrEmpty(word) || maxResults <= 0)
                {
                    return Array.Empty<string>();
                }
                CommandTable table = _tabTable;
                if (table is null)
                {
                    lock (_tabLock)
                    {
                        if (_tabTable is null)
                        {
                            _tabTable = LoadCommands();
                        }
                        table = _tabTable;
                    }
                }
                return FilterCommands(table, word, maxResults).ToArray();
            }
            catch
            {
                return Array.Empty<string>();
            }
        }

        public bool CanAcceptFeedback(PredictionClient client, PredictorFeedbackKind feedback) => false;
        public void OnSuggestionDisplayed(PredictionClient client, uint session, int countOrIndex) { }
        public void OnSuggestionAccepted(PredictionClient client, uint session, string acceptedSuggestion) { }
        public void OnCommandLineAccepted(PredictionClient client, IReadOnlyList<string> history) { }
        public void OnCommandLineExecuted(PredictionClient client, string commandLine, bool success) { }
    }
}
