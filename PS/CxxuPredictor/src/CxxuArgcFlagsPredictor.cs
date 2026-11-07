using System;
using System.Collections.Generic;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Language;
using System.Management.Automation.Subsystem.Prediction;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

namespace CxxuPredictor
{
    // 静态参数提示 predictor:只处理 argc-completions 覆盖的应用命令的“首个参数位”，
    // 且当前词以 '-' 开头。数据来自 completions/*.sh 顶层的 @flag/@option 注释:
    // 构建一次写入 ~/.cxxu/cache/argc-flags.tsv，后续会话直接读表;
    // 每次预测只做字典查询 + 前缀过滤，不启动 argc/bash，亚毫秒级。
    // 范围取舍见 docs/Feature-Guide.md「参数自动提示」与 Startup-Optimization.md 对应轮次。
    public sealed class CxxuArgcFlagsPredictor : ICommandPredictor
    {
        // ListView 一屏约 10 行(历史占前几行);参数提示给 10 条足够。
        private const int PredictorMaxResults = 10;
        private const int MaxDescLength = 160;

        private readonly Guid _guid;
        private readonly object _sync = new object();
        private Dictionary<string, List<FlagEntry>> _table;
        private volatile bool _loaded;

        internal sealed class FlagEntry
        {
            public string Flag;
            public bool TakesValue;
            public string Description;
        }

        internal CxxuArgcFlagsPredictor(string guid)
        {
            _guid = new Guid(guid);
            // 表在 OnIdle 装载阶段构建/读取一次:首屏单发已允许 ~百毫秒,
            // 避免把首次预测拖慢。禁用(argc 关)或仓库未定位时跳过,
            // 后续 Enable / Set-ArgcCompletions 设置好环境变量后再懒建。
            if (!IsDisabled())
            {
                _table = GetTable();
            }
        }

        public Guid Id => _guid;
        public string Name => "CxxuArgcFlags";
        public string Description => "Static argc-completions flag/option hints for the first argument position of covered application commands.";

        public SuggestionPackage GetSuggestion(PredictionClient client, PredictionContext context, CancellationToken cancellationToken)
        {
            if (context is null || IsDisabled())
            {
                return default;
            }

            Token token = context.TokenAtCursor;
            if (token is null || token.TokenFlags.HasFlag(TokenFlags.CommandName))
            {
                return default;
            }

            string typed = token.Text;
            if (string.IsNullOrEmpty(typed) || typed[0] != '-' || typed.Length > 64)
            {
                return default;
            }

            Dictionary<string, List<FlagEntry>> table = GetTable();
            if (table is null || table.Count == 0)
            {
                return default;
            }

            CommandAst cmdAst = FindInnermostCommandAst(context.InputAst, token);
            if (cmdAst is null)
            {
                return default;
            }

            // 只覆盖首个参数位:命令名 + 当前词(2 个元素),更深的位置留给 Tab(argc 现场算)。
            var elements = cmdAst.CommandElements;
            if (elements.Count != 2)
            {
                return default;
            }
            if (elements[1].Extent.StartOffset != token.Extent.StartOffset)
            {
                return default;
            }

            string command = cmdAst.GetCommandName();
            if (string.IsNullOrEmpty(command))
            {
                return default;
            }
            command = NormalizeCommandName(command);
            if (string.IsNullOrEmpty(command) || !table.TryGetValue(command, out List<FlagEntry> flags))
            {
                return default;
            }

            string input = context.InputAst.Extent.Text;
            int headLength = token.Extent.StartOffset;
            if (input is null || headLength < 0 || headLength > input.Length)
            {
                return default;
            }
            string head = input.Substring(0, headLength);

            List<PredictiveSuggestion> suggestions = null;
            foreach (FlagEntry entry in flags)
            {
                if (cancellationToken.IsCancellationRequested)
                {
                    return default;
                }
                if (!entry.Flag.StartsWith(typed, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }
                string suggestion = head + entry.Flag + (entry.TakesValue ? " " : string.Empty);
                if (string.Equals(suggestion, input, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }
                if (suggestions is null)
                {
                    suggestions = new List<PredictiveSuggestion>(PredictorMaxResults);
                }
                suggestions.Add(new PredictiveSuggestion(suggestion, entry.Description));
                if (suggestions.Count >= PredictorMaxResults)
                {
                    break;
                }
            }

            return suggestions is null ? default : new SuggestionPackage(suggestions);
        }

        private static bool IsDisabled()
        {
            string value = Environment.GetEnvironmentVariable("PsArgc");
            if (string.IsNullOrWhiteSpace(value))
            {
                return false;
            }
            value = value.Trim();
            return value.Equals("False", StringComparison.OrdinalIgnoreCase)
                || value == "0"
                || value.Equals("No", StringComparison.OrdinalIgnoreCase)
                || value.Equals("Off", StringComparison.OrdinalIgnoreCase);
        }

        // 只去掉可执行后缀:命令名里本来就可能带点(python3.11、node18.exe 以外的场景)
        private static string NormalizeCommandName(string command)
        {
            string name = Path.GetFileName(command);
            if (name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ||
                name.EndsWith(".cmd", StringComparison.OrdinalIgnoreCase) ||
                name.EndsWith(".bat", StringComparison.OrdinalIgnoreCase) ||
                name.EndsWith(".com", StringComparison.OrdinalIgnoreCase))
            {
                name = Path.GetFileNameWithoutExtension(name);
            }
            return name;
        }

        private static CommandAst FindInnermostCommandAst(Ast inputAst, Token token)
        {
            if (inputAst is null)
            {
                return null;
            }
            CommandAst best = null;
            foreach (Ast node in inputAst.FindAll(ast => ast is CommandAst, searchNestedScriptBlocks: true))
            {
                CommandAst candidate = (CommandAst)node;
                if (candidate.Extent.StartOffset > token.Extent.StartOffset ||
                    candidate.Extent.EndOffset < token.Extent.EndOffset)
                {
                    continue;
                }
                if (best is null || candidate.Extent.StartOffset > best.Extent.StartOffset)
                {
                    best = candidate;
                }
            }
            return best;
        }

        private Dictionary<string, List<FlagEntry>> GetTable()
        {
            if (_loaded)
            {
                return _table;
            }
            lock (_sync)
            {
                if (_loaded)
                {
                    return _table;
                }
                // 仓库路径还没设好时不落缓存,等 Set-ArgcCompletions 设置后再建。
                if (GetRoot() is null)
                {
                    return null;
                }
                _table = LoadOrBuildTable();
                _loaded = true;
                return _table;
            }
        }

        private static string GetRoot()
        {
            string root = Environment.GetEnvironmentVariable("ARGC_COMPLETIONS_ROOT");
            return string.IsNullOrWhiteSpace(root) ? null : root.Trim();
        }

        private static string GetCachePath()
        {
            string cache = Environment.GetEnvironmentVariable("CXXU_ARGC_FLAGS");
            if (!string.IsNullOrWhiteSpace(cache))
            {
                return cache.Trim();
            }
            string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            return Path.Combine(home, ".cxxu", "cache", "argc-flags.tsv");
        }

        private static IEnumerable<string> GetCompletionDirs(string root)
        {
            yield return Path.Combine(root, "completions");
            yield return Path.Combine(root, "completions", "windows");
        }

        private static Dictionary<string, List<FlagEntry>> LoadOrBuildTable()
        {
            Dictionary<string, List<FlagEntry>> table =
                new Dictionary<string, List<FlagEntry>>(StringComparer.OrdinalIgnoreCase);
            try
            {
                string root = GetRoot();
                if (root is null)
                {
                    return table;
                }
                string cache = GetCachePath();
                if (NeedBuild(root, cache))
                {
                    BuildTable(root, cache);
                }
                if (!File.Exists(cache))
                {
                    return table;
                }
                foreach (string line in File.ReadLines(cache, Encoding.UTF8))
                {
                    if (line.Length == 0)
                    {
                        continue;
                    }
                    string[] parts = line.Split('\t');
                    if (parts.Length < 4)
                    {
                        continue;
                    }
                    string command = parts[0];
                    if (command.Length == 0 || parts[1].Length == 0)
                    {
                        continue;
                    }
                    if (!table.TryGetValue(command, out List<FlagEntry> list))
                    {
                        list = new List<FlagEntry>();
                        table[command] = list;
                    }
                    list.Add(new FlagEntry
                    {
                        Flag = parts[1],
                        TakesValue = parts[2] == "1",
                        Description = parts[3],
                    });
                }
            }
            catch
            {
                // 表构建/读取失败时静默降级为“无参数提示”，不影响其它预测源与 Tab 补全。
            }
            return table;
        }

        private static bool NeedBuild(string root, string cache)
        {
            if (!File.Exists(cache))
            {
                return true;
            }
            DateTime cacheTime = File.GetLastWriteTimeUtc(cache);
            foreach (string dir in GetCompletionDirs(root))
            {
                if (!Directory.Exists(dir))
                {
                    continue;
                }
                foreach (string file in Directory.EnumerateFiles(dir, "*.sh"))
                {
                    if (File.GetLastWriteTimeUtc(file) > cacheTime)
                    {
                        return true;
                    }
                }
            }
            return false;
        }

        // 解析 argc 生成脚本顶层的 @flag/@option 注释(遇到第一个 "# {{" 子命令块即停)。
        // 行格式:# @flag -p --paginate   描述  /  # @option -s[`_x`] <signal>   描述
        private static void BuildTable(string root, string cache)
        {
            Regex lineRx = new Regex(@"^\s*#\s*@(flag|option)\s+(.+)$", RegexOptions.Compiled);
            Regex gapRx = new Regex("[ ]{2,}", RegexOptions.Compiled);
            // 去重键必须区分大小写:-v 与 -V、-t 与 -T 是不同参数。
            Dictionary<string, string> rows = new Dictionary<string, string>(StringComparer.Ordinal);
            List<string> order = new List<string>();

            foreach (string dir in GetCompletionDirs(root))
            {
                if (!Directory.Exists(dir))
                {
                    continue;
                }
                foreach (string file in Directory.EnumerateFiles(dir, "*.sh"))
                {
                    string command = Path.GetFileNameWithoutExtension(file);
                    if (string.IsNullOrEmpty(command))
                    {
                        continue;
                    }
                    string text;
                    try
                    {
                        text = File.ReadAllText(file, Encoding.UTF8);
                    }
                    catch
                    {
                        continue;
                    }
                    int cut = text.IndexOf("# {{", StringComparison.Ordinal);
                    if (cut >= 0)
                    {
                        text = text.Substring(0, cut);
                    }
                    foreach (string rawLine in text.Split('\n'))
                    {
                        Match match = lineRx.Match(rawLine);
                        if (!match.Success)
                        {
                            continue;
                        }
                        string kind = match.Groups[1].Value;
                        string rest = match.Groups[2].Value.TrimEnd('\r').Trim();
                        if (rest.Length == 0)
                        {
                            continue;
                        }

                        string signature = rest;
                        string description = string.Empty;
                        Match gap = gapRx.Match(rest);
                        if (gap.Success)
                        {
                            signature = rest.Substring(0, gap.Index);
                            description = rest.Substring(gap.Index).Trim();
                        }
                        if (description.Length > MaxDescLength)
                        {
                            description = description.Substring(0, MaxDescLength);
                        }
                        description = description.Replace('\t', ' ').Replace('\r', ' ').Replace('\n', ' ');

                        string[] tokens = signature.Split(new char[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
                        bool hasSeparateValue = false;
                        for (int i = 0; i < tokens.Length; i++)
                        {
                            if (tokens[i].StartsWith("<", StringComparison.Ordinal))
                            {
                                hasSeparateValue = true;
                                break;
                            }
                        }
                        // @option 且值以空格分隔时才补尾随空格;内联值(-bso/-aoa)不补。
                        bool takesValue = kind == "option" && hasSeparateValue;

                        foreach (string token in tokens)
                        {
                            if (token.Length == 0 || token[0] != '-')
                            {
                                continue;
                            }
                            string flag = token;
                            bool inlineValue = false;
                            int bracket = flag.IndexOf('[');
                            if (bracket > 0)
                            {
                                inlineValue = true;
                                flag = flag.Substring(0, bracket);
                            }
                            if (inlineValue && flag.EndsWith("-", StringComparison.Ordinal))
                            {
                                flag = flag.TrimEnd('-');
                            }
                            if (flag.Length < 2)
                            {
                                continue;
                            }
                            string key = command + "\t" + flag;
                            if (rows.ContainsKey(key))
                            {
                                continue;
                            }
                            rows[key] = command + "\t" + flag + "\t" + (takesValue ? "1" : "0") + "\t" + description;
                            order.Add(key);
                        }
                    }
                }
            }

            string dirName = Path.GetDirectoryName(cache);
            if (!string.IsNullOrEmpty(dirName))
            {
                Directory.CreateDirectory(dirName);
            }
            StringBuilder builder = new StringBuilder();
            foreach (string key in order)
            {
                builder.Append(rows[key]).Append('\n');
            }
            string tmp = cache + ".tmp";
            File.WriteAllText(tmp, builder.ToString(), new UTF8Encoding(false));
            File.Move(tmp, cache, overwrite: true);
        }
    }
}
