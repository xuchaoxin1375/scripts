<?php
/**
 * 日志分析系统 - Log Analyzer Pro
 * 支持大文件分析、实时图表、多维度统计
 */

// 配置
define('CHUNK_SIZE', 8192); // 每次读取的字节数
define('MAX_PREVIEW_LINES', 1000); // 预览时最大行数
define('MAX_MEMORY', '512M');
ini_set('memory_limit', MAX_MEMORY);
ini_set('max_execution_time', 300);

// API 请求处理
if (isset($_GET['action'])) {
    header('Content-Type: application/json; charset=utf-8');
    
    switch ($_GET['action']) {
        case 'list_logs':
            echo json_encode(listLogFiles());
            break;
        case 'analyze':
            echo json_encode(analyzeLog($_GET));
            break;
        case 'get_ips':
            echo json_encode(getIPsForTimeSlice($_GET));
            break;
        case 'file_info':
            echo json_encode(getFileInfo($_GET['file'] ?? ''));
            break;
        default:
            echo json_encode(['error' => 'Unknown action']);
    }

    exit;
}

function normalizePercentRange($params, $filesize) {
    $rangeStart = isset($params['range_start']) ? (float)$params['range_start'] : null;
    $rangeEnd = isset($params['range_end']) ? (float)$params['range_end'] : null;
    $tailPercent = isset($params['tail_percent']) ? (float)$params['tail_percent'] : null;

    if ($rangeStart === null || $rangeEnd === null) {
        if ($tailPercent !== null) {
            if ($tailPercent < 1) $tailPercent = 1;
            if ($tailPercent > 100) $tailPercent = 100;
            $rangeStart = 100 - $tailPercent;
            $rangeEnd = 100;
        } else {
            $rangeStart = 0;
            $rangeEnd = 100;
        }
    }

    if ($rangeStart < 0) $rangeStart = 0;
    if ($rangeEnd > 100) $rangeEnd = 100;
    if ($rangeEnd < 0) $rangeEnd = 0;
    if ($rangeStart > 100) $rangeStart = 100;
    if ($rangeEnd <= $rangeStart) {
        $rangeEnd = min(100, $rangeStart + 0.01);
    }

    $startOffset = (int)floor($filesize * ($rangeStart / 100));
    $endOffset = (int)floor($filesize * ($rangeEnd / 100));

    if ($endOffset <= $startOffset) {
        $endOffset = min($filesize, $startOffset + 1);
    }

    return [
        'range_start' => $rangeStart,
        'range_end' => $rangeEnd,
        'start_offset' => $startOffset,
        'end_offset' => $endOffset
    ];
}

/**
 * 列出目录下的所有日志文件
 */
function listLogFiles() {
    $files = [];
    $dir = __DIR__;
    
    foreach (glob($dir . '/*.log') as $file) {
        $files[] = [
            'name' => basename($file),
            'size' => filesize($file),
            'size_human' => formatBytes(filesize($file)),
            'modified' => date('Y-m-d H:i:s', filemtime($file))
        ];
    }
    
    usort($files, function($a, $b) {
        return $b['size'] - $a['size'];
    });
    
    return $files;
}

/**
 * 获取文件基本信息（快速扫描）
 */
function getFileInfo($filename) {
    $filepath = __DIR__ . '/' . basename($filename);
    
    if (!file_exists($filepath) || !is_readable($filepath)) {
        return ['error' => 'File not found or not readable'];
    }
    
    $filesize = filesize($filepath);
    $lineCount = 0;
    $firstTime = null;
    $lastTime = null;
    $sampleLines = [];
    
    $handle = fopen($filepath, 'r');
    if (!$handle) {
        return ['error' => 'Cannot open file'];
    }

    $range = normalizePercentRange($_GET, $filesize);
    $rangeStart = $range['range_start'];
    $rangeEnd = $range['range_end'];
    $startOffset = $range['start_offset'];
    $endOffset = $range['end_offset'];

    $startTime = $_GET['start'] ?? null;
    $endTime = $_GET['end'] ?? null;
    $startTs = $startTime ? strtotime($startTime) : null;
    $endTs = $endTime ? strtotime($endTime) : null;

    if ($filesize > 0) {
        fseek($handle, $startOffset);
        if ($startOffset > 0) {
            fgets($handle); // 跳过可能的不完整行
        }
    }

    $scanStartPos = ftell($handle);
    $scanEndPos = $endOffset;
    
    // 扫描选中区间（可叠加时间过滤）
    $lineNum = 0;
    while (($line = fgets($handle)) !== false) {
        $posAfter = ftell($handle);
        if ($posAfter !== false && $posAfter > $scanEndPos) {
            break;
        }

        $lineCount++;
        if ($lineNum < 5) {
            $sampleLines[] = trim($line);
        }
        $lineNum++;

        $time = extractTime($line);
        if ($time) {
            $ts = strtotime($time);
            if (($startTs && $ts < $startTs) || ($endTs && $ts > $endTs)) {
                continue;
            }
            if (!$firstTime) {
                $firstTime = $time;
            }
            $lastTime = $time;
        }
    }
    
    // 预估行数：
    // - 无时间过滤：用换行符快速估算
    // - 有时间过滤：按行扫描计数（更准确，但更慢；用户只有在需要日期筛选时才会触发）
    $scanSize = max(0, $scanEndPos - $scanStartPos);
    $estimatedLines = 0;

    if ($startTs || $endTs) {
        fseek($handle, $scanStartPos);
        if ($scanStartPos > 0) {
            fgets($handle);
        }
        while (($line = fgets($handle)) !== false) {
            $posAfter = ftell($handle);
            if ($posAfter !== false && $posAfter > $scanEndPos) {
                break;
            }
            $time = extractTime($line);
            if (!$time) continue;
            $ts = strtotime($time);
            if ($startTs && $ts < $startTs) continue;
            if ($endTs && $ts > $endTs) continue;
            $estimatedLines++;
        }
    } else {
        fseek($handle, $scanStartPos);
        while (!feof($handle)) {
            $pos = ftell($handle);
            if ($pos === false || $pos >= $scanEndPos) {
                break;
            }
            $readLen = (int)min(CHUNK_SIZE, $scanEndPos - $pos);
            $buf = fread($handle, $readLen);
            if ($buf === false || $buf === '') {
                break;
            }
            $estimatedLines += substr_count($buf, "\n");
        }
        if ($scanSize > 0 && $estimatedLines === 0) {
            $estimatedLines = 1;
        }
    }
    
    fclose($handle);
    
    // 计算时间跨度
    $timeSpan = null;
    $suggestedInterval = 60;
    
    if ($firstTime && $lastTime) {
        $start = strtotime($firstTime);
        $end = strtotime($lastTime);
        $spanSeconds = $end - $start;
        
        $timeSpan = [
            'start' => $firstTime,
            'end' => $lastTime,
            'seconds' => $spanSeconds,
            'human' => formatDuration($spanSeconds)
        ];
        
        // 根据时间跨度建议统计间隔
        if ($spanSeconds <= 300) {
            $suggestedInterval = 10;
        } elseif ($spanSeconds <= 1800) {
            $suggestedInterval = 30;
        } elseif ($spanSeconds <= 3600) {
            $suggestedInterval = 60;
        } elseif ($spanSeconds <= 21600) {
            $suggestedInterval = 300;
        } elseif ($spanSeconds <= 86400) {
            $suggestedInterval = 600;
        } else {
            $suggestedInterval = 1800;
        }
    }
    
    return [
        'filename' => $filename,
        'size' => $filesize,
        'size_human' => formatBytes($filesize),
        'estimated_lines' => $estimatedLines,
        'time_span' => $timeSpan,
        'suggested_interval' => $suggestedInterval,
        'sample_lines' => $sampleLines,
        'analysis' => [
            'range_start' => $rangeStart,
            'range_end' => $rangeEnd,
            'start_offset' => $scanStartPos,
            'end_offset' => $scanEndPos,
            'analyzed_bytes' => $scanSize
        ]
    ];
}

/**
 * 分析日志文件
 */
function analyzeLog($params) {
    $filename = basename($params['file'] ?? '');
    $filepath = __DIR__ . '/' . $filename;
    
    if (!file_exists($filepath) || !is_readable($filepath)) {
        return ['error' => 'File not found'];
    }
    
    $interval = (int)($params['interval'] ?? 60);
    $startTime = $params['start'] ?? null;
    $endTime = $params['end'] ?? null;
    $filesize = filesize($filepath);
    $range = normalizePercentRange($params, $filesize);
    $rangeStart = $range['range_start'];
    $rangeEnd = $range['range_end'];
    $startOffset = $range['start_offset'];
    $endOffset = $range['end_offset'];
    
    $startTs = $startTime ? strtotime($startTime) : null;
    $endTs = $endTime ? strtotime($endTime) : null;
    
    $data = [
        'timeline' => [],
        'status_codes' => [],
        'top_ips' => [],
        'top_urls' => [],
        'user_agents' => [],
        'domains' => [],
        'summary' => [
            'total_requests' => 0,
            'unique_ips' => 0,
            'status_breakdown' => [],
            'first_time' => null,
            'last_time' => null
        ]
    ];
    
    $timeSlots = [];
    $allIPs = [];
    $allURLs = [];
    $allUAs = [];
    $allDomains = [];
    $statusCounts = [];
    
    $handle = fopen($filepath, 'r');
    if (!$handle) {
        return ['error' => 'Cannot open file'];
    }

    if ($filesize > 0) {
        fseek($handle, $startOffset);
        if ($startOffset > 0) {
            fgets($handle); // 跳过可能的不完整行
        }
    }

    $scanStartPos = ftell($handle);
    $scanEndPos = $endOffset;
    
    $lineCount = 0;
    $processedCount = 0;
    
    while (($line = fgets($handle)) !== false) {
        $posAfter = ftell($handle);
        if ($posAfter !== false && $posAfter > $scanEndPos) {
            break;
        }
        $lineCount++;
        $parsed = parseLine($line);
        
        if (!$parsed) continue;
        
        $timestamp = strtotime($parsed['time']);
        
        // 时间范围过滤
        if ($startTs && $timestamp < $startTs) continue;
        if ($endTs && $timestamp > $endTs) continue;
        
        $processedCount++;
        
        // 记录时间范围
        if (!$data['summary']['first_time'] || $parsed['time'] < $data['summary']['first_time']) {
            $data['summary']['first_time'] = $parsed['time'];
        }
        if (!$data['summary']['last_time'] || $parsed['time'] > $data['summary']['last_time']) {
            $data['summary']['last_time'] = $parsed['time'];
        }
        
        // 时间槽统计
        $slotKey = floor($timestamp / $interval) * $interval;
        if (!isset($timeSlots[$slotKey])) {
            $timeSlots[$slotKey] = [
                'total' => 0,
                'status' => [],
                'ips' => []
            ];
        }
        
        $timeSlots[$slotKey]['total']++;
        $status = $parsed['status'];
        $statusGroup = substr($status, 0, 1) . 'xx';
        
        if (!isset($timeSlots[$slotKey]['status'][$status])) {
            $timeSlots[$slotKey]['status'][$status] = 0;
        }
        $timeSlots[$slotKey]['status'][$status]++;
        
        if (!in_array($parsed['ip'], $timeSlots[$slotKey]['ips'])) {
            $timeSlots[$slotKey]['ips'][] = $parsed['ip'];
        }
        
        // 全局统计
        if (!isset($allIPs[$parsed['ip']])) {
            $allIPs[$parsed['ip']] = 0;
        }
        $allIPs[$parsed['ip']]++;
        
        if (!isset($statusCounts[$status])) {
            $statusCounts[$status] = 0;
        }
        $statusCounts[$status]++;
        
        // URL统计（简化）
        $urlKey = $parsed['domain'] . parse_url($parsed['url'], PHP_URL_PATH);
        if (strlen($urlKey) > 100) {
            $urlKey = substr($urlKey, 0, 100) . '...';
        }
        if (!isset($allURLs[$urlKey])) {
            $allURLs[$urlKey] = 0;
        }
        $allURLs[$urlKey]++;
        
        // 域名统计
        if (!isset($allDomains[$parsed['domain']])) {
            $allDomains[$parsed['domain']] = 0;
        }
        $allDomains[$parsed['domain']]++;
        
        // UA统计（简化）
        $uaKey = simplifyUA($parsed['ua']);
        if (!isset($allUAs[$uaKey])) {
            $allUAs[$uaKey] = 0;
        }
        $allUAs[$uaKey]++;
        
        // 防止内存溢出，限制统计项数量
        if (count($allURLs) > 10000) {
            arsort($allURLs);
            $allURLs = array_slice($allURLs, 0, 5000, true);
        }
    }
    
    fclose($handle);
    
    // 填充缺失的时间段，确保图表连续
    if (!empty($timeSlots)) {
        // 确定开始和结束时间戳
        $minTs = min(array_keys($timeSlots));
        $maxTs = max(array_keys($timeSlots));
        
        // 如果用户指定了时间范围，使用用户指定的时间
        if ($startTs && $startTs < $minTs) $minTs = floor($startTs / $interval) * $interval;
        if ($endTs && $endTs > $maxTs) $maxTs = floor($endTs / $interval) * $interval;
        
        // 确保从整点开始
        $currentTs = $minTs;
        while ($currentTs <= $maxTs) {
            if (!isset($timeSlots[$currentTs])) {
                $timeSlots[$currentTs] = [
                    'total' => 0,
                    'status' => [],
                    'ips' => []
                ];
            }
            $currentTs += $interval;
        }
    }
    
    // 处理时间线数据
    ksort($timeSlots);
    $allStatusCodes = array_keys($statusCounts);
    sort($allStatusCodes);
    
    foreach ($timeSlots as $ts => $slot) {
        $point = [
            'time' => date('Y-m-d H:i:s', $ts),
            'timestamp' => $ts,
            'total' => $slot['total'],
            'unique_ips' => count($slot['ips'])
        ];
        
        foreach ($allStatusCodes as $code) {
            $point['status_' . $code] = $slot['status'][$code] ?? 0;
        }
        
        $data['timeline'][] = $point;
    }
    
    // Top IPs
    arsort($allIPs);
    $data['top_ips'] = array_slice($allIPs, 0, 50, true);
    
    // Top URLs
    arsort($allURLs);
    $data['top_urls'] = array_slice($allURLs, 0, 50, true);
    
    // Top UAs
    arsort($allUAs);
    $data['user_agents'] = array_slice($allUAs, 0, 20, true);
    
    // 域名统计
    arsort($allDomains);
    $data['domains'] = array_slice($allDomains, 0, 50, true);
    
    // 汇总
    $data['summary']['total_requests'] = $processedCount;
    $data['summary']['unique_ips'] = count($allIPs);
    $data['summary']['status_breakdown'] = $statusCounts;
    $data['status_codes'] = $allStatusCodes;
    $data['total_lines'] = $lineCount;
    $data['interval'] = $interval;
    $data['analysis'] = [
        'range_start' => $rangeStart,
        'range_end' => $rangeEnd,
        'start_offset' => $scanStartPos,
        'end_offset' => $scanEndPos,
        'analyzed_bytes' => max(0, $scanEndPos - $scanStartPos)
    ];
    
    return $data;
}

/**
 * 获取特定时间段的IP列表
 */
function getIPsForTimeSlice($params) {
    $filename = basename($params['file'] ?? '');
    $filepath = __DIR__ . '/' . $filename;
    $timestamp = (int)($params['timestamp'] ?? 0);
    $interval = (int)($params['interval'] ?? 60);
    
    if (!file_exists($filepath)) {
        return ['error' => 'File not found'];
    }

    $filesize = filesize($filepath);
    $range = normalizePercentRange($params, $filesize);
    $rangeStart = $range['range_start'];
    $rangeEnd = $range['range_end'];
    $startOffset = $range['start_offset'];
    $endOffset = $range['end_offset'];
    
    $startTs = $timestamp;
    $endTs = $timestamp + $interval;
    
    $ips = [];
    
    $handle = fopen($filepath, 'r');
    if (!$handle) {
        return ['error' => 'Cannot open file'];
    }

    if ($filesize > 0) {
        fseek($handle, $startOffset);
        if ($startOffset > 0) {
            fgets($handle); // 跳过可能的不完整行
        }
    }

    $scanStartPos = ftell($handle);
    $scanEndPos = $endOffset;

    while (($line = fgets($handle)) !== false) {
        $posAfter = ftell($handle);
        if ($posAfter !== false && $posAfter > $scanEndPos) {
            break;
        }
        $parsed = parseLine($line);
        if (!$parsed) continue;
        
        $ts = strtotime($parsed['time']);
        if ($ts >= $startTs && $ts < $endTs) {
            if (!isset($ips[$parsed['ip']])) {
                $ips[$parsed['ip']] = [
                    'count' => 0,
                    'statuses' => [],
                    'urls' => []
                ];
            }
            $ips[$parsed['ip']]['count']++;
            
            if (!isset($ips[$parsed['ip']]['statuses'][$parsed['status']])) {
                $ips[$parsed['ip']]['statuses'][$parsed['status']] = 0;
            }
            $ips[$parsed['ip']]['statuses'][$parsed['status']]++;
            
            if (!isset($ips[$parsed['ip']]['urls'])) {
                $ips[$parsed['ip']]['urls'] = [];
            }
            // 存储 URL 和对应的状态码
            // 为了防止完全重复的记录以节省空间，可以简单检查
            // 但如果用户想要完整的访问记录序列，则直接追加
            $ips[$parsed['ip']]['urls'][] = [
                'url' => $parsed['url'],
                'status' => $parsed['status']
            ];
        }
    }
    fclose($handle);
    
    // 按请求数排序
    uasort($ips, function($a, $b) {
        return $b['count'] - $a['count'];
    });
    
    return [
        'time_start' => date('Y-m-d H:i:s', $startTs),
        'time_end' => date('Y-m-d H:i:s', $endTs),
        'analysis' => [
            'range_start' => $rangeStart,
            'range_end' => $rangeEnd,
            'start_offset' => $scanStartPos,
            'end_offset' => $scanEndPos,
            'analyzed_bytes' => max(0, $scanEndPos - $scanStartPos)
        ],
        'ips' => $ips
    ];
}

/**
 * 解析日志行
 */
function parseLine($line) {
    // 格式: IP [time] status=XXX [METHOD] [req = URL] UA="..." referer="..."
    $pattern = '/^(\S+)\s+\[([^\]]+)\]\s+status=(\d+)\s+\[(\w+)\]\s+\[req\s*=\s*([^\]]+)\]\s+UA="([^"]*)"/';
    
    if (preg_match($pattern, $line, $matches)) {
        $url = trim($matches[5]);
        $domain = '';
        
        if (preg_match('/^([^\/]+)/', $url, $domainMatch)) {
            $domain = $domainMatch[1];
        }
        
        return [
            'ip' => $matches[1],
            'time' => $matches[2],
            'status' => $matches[3],
            'method' => $matches[4],
            'url' => $url,
            'domain' => $domain,
            'ua' => $matches[6]
        ];
    }
    
    return null;
}

/**
 * 从日志行提取时间
 */
function extractTime($line) {
    if (preg_match('/\[([^\]]+)\]/', $line, $matches)) {
        return $matches[1];
    }
    return null;
}

/**
 * 简化User-Agent
 */
function simplifyUA($ua) {
    if (stripos($ua, 'Googlebot') !== false) return 'Googlebot';
    if (stripos($ua, 'Bingbot') !== false) return 'Bingbot';
    if (stripos($ua, 'baiduspider') !== false) return 'Baiduspider';
    if (stripos($ua, 'YandexBot') !== false) return 'YandexBot';
    if (stripos($ua, 'DotBot') !== false) return 'DotBot';
    if (stripos($ua, 'AhrefsBot') !== false) return 'AhrefsBot';
    if (stripos($ua, 'SemrushBot') !== false) return 'SemrushBot';
    if (stripos($ua, 'MJ12bot') !== false) return 'MJ12bot';
    if (stripos($ua, 'Python') !== false) return 'Python Script';
    if (stripos($ua, 'curl') !== false) return 'cURL';
    if (stripos($ua, 'Chrome') !== false) return 'Chrome Browser';
    if (stripos($ua, 'Firefox') !== false) return 'Firefox Browser';
    if (stripos($ua, 'Safari') !== false) return 'Safari Browser';
    if (stripos($ua, 'Edge') !== false) return 'Edge Browser';
    if (strlen($ua) < 50) return $ua;
    return substr($ua, 0, 50) . '...';
}

/**
 * 格式化字节数
 */
function formatBytes($bytes) {
    $units = ['B', 'KB', 'MB', 'GB', 'TB'];
    $i = 0;
    while ($bytes >= 1024 && $i < count($units) - 1) {
        $bytes /= 1024;
        $i++;
    }
    return round($bytes, 2) . ' ' . $units[$i];
}

/**
 * 格式化时间段
 */
function formatDuration($seconds) {
    if ($seconds < 60) return $seconds . ' 秒';
    if ($seconds < 3600) return round($seconds / 60, 1) . ' 分钟';
    if ($seconds < 86400) return round($seconds / 3600, 1) . ' 小时';
    return round($seconds / 86400, 1) . ' 天';
}

?>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>日志分析系统 - Log Analyzer Pro</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chartjs-adapter-date-fns"></script>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        :root {
            /* Default Light Mode (Slate based) */
            --bg-primary: #f8fafc;
            --bg-secondary: #ffffff;
            --bg-tertiary: #f1f5f9;
            --text-primary: #0f172a;
            --text-secondary: #64748b;
            --accent-blue: #3b82f6;
            --accent-green: #22c55e;
            --accent-yellow: #eab308;
            --accent-red: #ef4444;
            --accent-purple: #a855f7;
            --border-color: #cbd5e1;
            --chart-grid-color: #e2e8f0;
            --chart-text-color: #64748b;
        }

        [data-theme="dark"] {
            --bg-primary: #0f172a;
            --bg-secondary: #1e293b;
            --bg-tertiary: #334155;
            --text-primary: #f1f5f9;
            --text-secondary: #94a3b8;
            --accent-blue: #3b82f6;
            --accent-green: #22c55e;
            --accent-yellow: #eab308;
            --accent-red: #ef4444;
            --accent-purple: #a855f7;
            --border-color: #475569;
            --chart-grid-color: #334155;
            --chart-text-color: #94a3b8;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            background: var(--bg-primary);
            color: var(--text-primary);
            line-height: 1.6;
            min-height: 100vh;
        }
        
        .container {
            max-width: 1600px;
            margin: 0 auto;
            padding: 20px;
        }
        
        header {
            background: linear-gradient(135deg, var(--bg-secondary), var(--bg-tertiary));
            padding: 20px;
            border-radius: 12px;
            margin-bottom: 20px;
            border: 1px solid var(--border-color);
        }
        
        header h1 {
            font-size: 1.8rem;
            margin-bottom: 5px;
            background: linear-gradient(90deg, var(--accent-blue), var(--accent-purple));
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
        }
        
        header p {
            color: var(--text-secondary);
            font-size: 0.9rem;
        }
        
        .card {
            background: var(--bg-secondary);
            border-radius: 12px;
            padding: 20px;
            margin-bottom: 20px;
            border: 1px solid var(--border-color);
        }
        
        .card-title {
            font-size: 1.1rem;
            font-weight: 600;
            margin-bottom: 15px;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        
        .card-title::before {
            content: '';
            width: 4px;
            height: 20px;
            background: var(--accent-blue);
            border-radius: 2px;
        }
        
        .controls-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-bottom: 15px;
        }
        
        .form-group {
            display: flex;
            flex-direction: column;
            gap: 5px;
        }
        
        .form-group label {
            font-size: 0.85rem;
            color: var(--text-secondary);
        }
        
        select, input {
            background: var(--bg-tertiary);
            border: 1px solid var(--border-color);
            border-radius: 8px;
            padding: 10px 12px;
            color: var(--text-primary);
            font-size: 0.95rem;
            transition: border-color 0.2s;
        }
        
        select:focus, input:focus {
            outline: none;
            border-color: var(--accent-blue);
        }
        
        button {
            background: var(--accent-blue);
            color: white;
            border: none;
            border-radius: 8px;
            padding: 10px 20px;
            font-size: 0.95rem;
            cursor: pointer;
            transition: all 0.2s;
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
        }
        
        button:hover {
            background: #2563eb;
            transform: translateY(-1px);
        }
        
        button:disabled {
            background: #726a61cb;
            cursor: not-allowed;
            transform: none;
        }
        
        .btn-secondary {
            background: #c8761994;
        }
        
        .btn-secondary:hover {
            background: var(--border-color);
        }
        
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 15px;
            margin-bottom: 20px;
        }
        
        .stat-card {
            background: var(--bg-tertiary);
            border-radius: 10px;
            padding: 15px;
            text-align: center;
        }
        
        .stat-value {
            font-size: 1.8rem;
            font-weight: 700;
            margin-bottom: 5px;
        }
        
        .stat-label {
            font-size: 0.85rem;
            color: var(--text-secondary);
        }
        
        .stat-card.blue .stat-value { color: var(--accent-blue); }
        .stat-card.green .stat-value { color: var(--accent-green); }
        .stat-card.yellow .stat-value { color: var(--accent-yellow); }
        .stat-card.red .stat-value { color: var(--accent-red); }
        .stat-card.purple .stat-value { color: var(--accent-purple); }
        
        .chart-container {
            position: relative;
            height: 400px;
            margin-bottom: 20px;
        }
        
        .legend-container {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
            margin-bottom: 15px;
        }
        
        .legend-item {
            display: flex;
            align-items: center;
            gap: 6px;
            padding: 6px 12px;
            background: var(--bg-tertiary);
            border-radius: 20px;
            cursor: pointer;
            transition: all 0.2s;
            font-size: 0.85rem;
        }
        
        .legend-item:hover {
            background: var(--border-color);
        }
        
        .legend-item.disabled {
            opacity: 0.4;
        }
        
        .legend-color {
            width: 12px;
            height: 12px;
            border-radius: 3px;
        }
        
        .data-table {
            width: 100%;
            border-collapse: collapse;
            font-size: 0.9rem;
        }
        
        .data-table th,
        .data-table td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid var(--border-color);
        }
        
        .data-table th {
            background: var(--bg-tertiary);
            font-weight: 600;
            color: var(--text-secondary);
            position: sticky;
            top: 0;
        }
        
        .data-table tr:hover {
            background: var(--bg-tertiary);
        }
        
        .table-scroll {
            max-height: 400px;
            overflow-y: auto;
        }
        
        .badge {
            display: inline-block;
            padding: 3px 8px;
            border-radius: 4px;
            font-size: 0.8rem;
            font-weight: 600;
        }
        
        .badge-success { background: rgba(34, 197, 94, 0.2); color: var(--accent-green); }
        .badge-warning { background: rgba(234, 179, 8, 0.2); color: var(--accent-yellow); }
        .badge-error { background: rgba(239, 68, 68, 0.2); color: var(--accent-red); }
        .badge-info { background: rgba(59, 130, 246, 0.2); color: var(--accent-blue); }
        
        .file-info {
            background: var(--bg-tertiary);
            border-radius: 8px;
            padding: 15px;
            margin-top: 15px;
        }
        
        .file-info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 15px;
        }
        
        .file-info-item {
            text-align: center;
        }
        
        .file-info-value {
            font-size: 1.2rem;
            font-weight: 600;
            color: var(--accent-blue);
        }
        
        .file-info-label {
            font-size: 0.8rem;
            color: var(--text-secondary);
        }
        
        .loading {
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 40px;
            color: var(--text-secondary);
        }
        
        .spinner {
            width: 40px;
            height: 40px;
            border: 3px solid var(--bg-tertiary);
            border-top-color: var(--accent-blue);
            border-radius: 50%;
            animation: spin 1s linear infinite;
            margin-right: 15px;
        }
        
        @keyframes spin {
            to { transform: rotate(360deg); }
        }
        
        .progress-bar {
            height: 4px;
            background: var(--bg-tertiary);
            border-radius: 2px;
            overflow: hidden;
            margin-top: 10px;
        }
        
        .progress-fill {
            height: 100%;
            background: var(--accent-blue);
            transition: width 0.3s;
        }
        
        .tabs {
            display: flex;
            gap: 5px;
            margin-bottom: 20px;
            flex-wrap: wrap;
        }
        
        .tab {
            padding: 10px 20px;
            background: var(--bg-tertiary);
            border: none;
            border-radius: 8px;
            color: var(--text-secondary);
            cursor: pointer;
            transition: all 0.2s;
        }
        
        .tab.active {
            background: var(--accent-blue);
            color: white;
        }
        
        .tab:hover:not(.active) {
            background: var(--border-color);
        }
        
        .tab-content {
            display: none;
        }
        
        .tab-content.active {
            display: block;
        }
        
        .modal {
            display: none;
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: rgba(0, 0, 0, 0.7);
            z-index: 1000;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        
        .modal.active {
            display: flex;
        }
        
        .modal-content {
            background: var(--bg-secondary);
            border-radius: 12px;
            max-width: 900px;
            width: 100%;
            max-height: 80vh;
            overflow: hidden;
            border: 1px solid var(--border-color);
        }
        
        .modal-header {
            padding: 20px;
            border-bottom: 1px solid var(--border-color);
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        
        .modal-body {
            padding: 20px;
            overflow-y: auto;
            max-height: calc(80vh - 70px);
        }
        
        .close-btn {
            background: none;
            border: none;
            color: var(--text-secondary);
            font-size: 1.5rem;
            cursor: pointer;
            padding: 5px;
        }
        
        .close-btn:hover {
            color: var(--text-primary);
        }
        
        .ip-list-container {
            border: 1px solid var(--border-color);
            border-radius: 8px;
            overflow: hidden;
            background: var(--bg-secondary);
        }

        .ip-list-header {
            display: grid;
            grid-template-columns: 1fr 100px 40px;
            padding: 10px 15px;
            background: var(--bg-tertiary);
            border-bottom: 1px solid var(--border-color);
            font-weight: 600;
            color: var(--text-secondary);
            font-size: 0.85rem;
            align-items: center;
        }

        .ip-item {
            border-bottom: 1px solid var(--border-color);
            background: var(--bg-secondary);
        }

        .ip-item:last-child {
            border-bottom: none;
        }

        .ip-row-main {
            display: grid;
            grid-template-columns: 1fr 100px 40px;
            padding: 12px 15px;
            align-items: center;
            cursor: pointer;
            transition: background 0.2s;
        }

        .ip-row-main:hover {
            background: var(--bg-tertiary);
        }

        .ip-address {
            font-family: monospace;
            font-size: 1rem;
            color: var(--accent-blue);
            font-weight: 500;
        }

        .ip-count {
            font-weight: 600;
            text-align: right;
            padding-right: 15px;
        }

        .toggle-icon {
            color: var(--text-secondary);
            transition: transform 0.3s;
            text-align: center;
            font-size: 0.8rem;
        }

        .ip-item.active .toggle-icon {
            transform: rotate(180deg);
        }

        .ip-details {
            display: none;
            padding: 0 15px 15px 15px;
            background: var(--bg-primary); /* Slightly distinct background */
            border-top: 1px dashed var(--border-color);
            font-size: 0.9rem;
        }

        .ip-item.active .ip-details {
            display: block;
        }

        .detail-section {
            margin-top: 10px;
        }

        .detail-title {
            font-size: 0.75rem;
            color: var(--text-secondary);
            text-transform: uppercase;
            letter-spacing: 0.5px;
            margin-bottom: 5px;
            font-weight: 600;
        }

        .url-list {
            list-style: none;
        }

        .url-list li {
            padding: 4px 0;
            border-bottom: 1px solid var(--border-color);
            font-family: monospace;
            font-size: 0.85rem;
            word-break: break-all;
            color: var(--text-secondary);
        }

        .url-list li:last-child {
            border-bottom: none;
        }

        
        @media (max-width: 768px) {
            .two-column {
                grid-template-columns: 1fr;
            }
            
            .chart-container {
                height: 200px;
            }
            
            .container {
                padding: 10px;
            }
            
            .card {
                padding: 10px;
                margin-bottom: 10px;
            }
            
            header h1 {
                font-size: 1.4rem;
            }
            
            .stats-grid {
                grid-template-columns: repeat(2, 1fr);
            }
            
            .stat-value {
                font-size: 1.4rem;
            }
            
            .legend-container {
                gap: 5px;
            }
            
            .legend-item {
                padding: 4px 8px;
                font-size: 0.75rem;
            }
        }
        
        .url-cell {
            max-width: 400px;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            font-family: monospace;
            font-size: 0.85rem;
        }
        
        .empty-state {
            text-align: center;
            padding: 60px 20px;
            color: var(--text-secondary);
        }
        
        .empty-state svg {
            width: 80px;
            height: 80px;
            margin-bottom: 20px;
            opacity: 0.5;
        }
        .fullscreen-btn {
            background: transparent;
            border: 1px solid var(--border-color);
            color: var(--text-secondary);
            padding: 5px 10px;
            font-size: 0.9rem;
            border-radius: 6px;
        }

        .fullscreen-btn:hover {
            background: var(--bg-tertiary);
            color: var(--text-primary);
        }

        .fullscreen-mode {
            position: fixed;
            top: 0;
            left: 0;
            width: 100vw;
            height: 100vh;
            background: var(--bg-secondary);
            z-index: 9999;
            padding: 20px;
            display: flex;
            flex-direction: column;
        }

        .fullscreen-mode .chart-container {
            flex: 1;
            height: auto;
            margin: 0;
        }

        .fullscreen-mode .card-title {
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <div style="display: flex; justify-content: space-between; align-items: flex-start;">
                <div>
                    <h1>📊 日志分析系统</h1>
                    <p>Log Analyzer Pro - 支持大文件分析、实时图表、多维度统计
                        <strong>(使用说明由于日志切割和截断问题,统计图表的边缘通常不准确)</strong>

                        </p>
                </div>
                <button id="themeToggle" class="btn-secondary" onclick="toggleTheme()" title="切换主题">
                    <span id="themeIcon">🌙</span>
                </button>
            </div>
        </header>
        
        <div class="card">
            <div class="card-title">文件选择与分析设置</div>
            <div class="controls-grid">
                <div class="form-group">
                    <label>选择日志文件</label>
                    <select id="logFile" onchange="onLogFileChange()">
                        <option value="">-- 请选择日志文件 --</option>
                    </select>
                </div>
                <div class="form-group">
                    <label>区间选择模式</label>
                    <select id="rangeMode" onchange="onRangeModeChange()">
                        <option value="percent" selected>百分比区间</option>
                        <option value="datetime">日期时间区间</option>
                    </select>
                </div>
                <div class="form-group" id="percentRangeGroup">
                    <label>按百分比区间截取</label>
                    <div style="display:flex; flex-direction:column; gap:8px;">
                        <select id="rangePreset" onchange="applyRangePreset()">
                            <option value="full" selected>0% ~ 100%（全量）</option>
                            <option value="tail50">50% ~ 100%（末尾50%）</option>
                            <option value="tail20">80% ~ 100%（末尾20%）</option>
                            <option value="tail10">90% ~ 100%（末尾10%）</option>
                            <option value="tail5">95% ~ 100%（末尾5%）</option>
                            <option value="custom">自定义区间</option>
                        </select>
                        <div style="display:flex; gap:10px; align-items:center;">
                            <input type="range" id="rangeStart" min="0" max="100" step="0.1" value="0" oninput="onRangeInput('start')" style="flex:1;">
                            <input type="range" id="rangeEnd" min="0" max="100" step="0.1" value="100" oninput="onRangeInput('end')" style="flex:1;">
                        </div>
                        <div style="display:flex; justify-content: space-between; font-size: 0.85rem; color: var(--text-secondary);">
                            <span>起始：<b id="rangeStartLabel" style="color: var(--text-primary);">0%</b></span>
                            <span>结束：<b id="rangeEndLabel" style="color: var(--text-primary);">100%</b></span>
                        </div>
                    </div>
                </div>
                <div class="form-group">
                    <label>统计间隔</label>
                    <select id="interval">
                        <option value="10">10 秒</option>
                        <option value="30">30 秒</option>
                        <option value="60" selected>1 分钟</option>
                        <option value="300">5 分钟</option>
                        <option value="600">10 分钟</option>
                        <option value="1800">30 分钟</option>
                        <option value="3600">1 小时</option>
                    </select>
                </div>
                <div id="dateTimeRangeGroup" style="display: none;" class="controls-grid">
                    <div class="form-group">
                        <label>开始时间</label>
                        <input type="datetime-local" id="startTime" disabled>
                    </div>
                    <div class="form-group">
                        <label>结束时间</label>
                        <input type="datetime-local" id="endTime" disabled>
                    </div>
                </div>
            </div>
            <div style="display: flex; gap: 10px; flex-wrap: wrap;">
                <button onclick="analyze()" id="analyzeBtn">
                    <span>🔍</span> 开始分析
                </button>
                <button class="btn-secondary" onclick="clearFilters()">
                    <span>🔄</span> 重置筛选
                </button>
            </div>
            
            <div id="fileInfo" class="file-info" style="display: none;"></div>
        </div>
        
        <div id="loadingIndicator" class="loading" style="display: none;">
            <div class="spinner"></div>
            <span>正在分析日志文件，请稍候...</span>
        </div>
        
        <div id="resultsSection" style="display: none;">
            <!-- 统计概览 -->
            <div class="stats-grid" id="statsGrid"></div>
            
            <!-- 图表区域 -->
            <div class="card" id="chartCard">
                <div class="card-title">
                    <span>请求时间线</span>
                    <button class="fullscreen-btn" onclick="toggleFullscreen()" title="全屏查看">
                        <span id="fsIcon">⛶</span> 全屏
                    </button>
                </div>
                <div class="legend-container" id="legendContainer"></div>
                <div class="chart-container">
                    <canvas id="mainChart"></canvas>
                </div>
                <p style="font-size: 0.85rem; color: var(--text-secondary); text-align: center;">
                    提示：点击图表上的数据点可查看该时间段的IP详情
                </p>
            </div>
            
            <!-- 选项卡区域 -->
            <div class="tabs">
                <button class="tab active" onclick="switchTab('ips')">🌐 Top IP</button>
                <button class="tab" onclick="switchTab('urls')">🔗 Top URL</button>
                <button class="tab" onclick="switchTab('domains')">🏠 域名统计</button>
                <button class="tab" onclick="switchTab('agents')">🤖 User-Agent</button>
                <button class="tab" onclick="switchTab('status')">📊 状态码分布</button>
            </div>
            
            <div id="tab-ips" class="tab-content active">
                <div class="card">
                    <div class="card-title">访问量最高的IP地址</div>
                    <div class="table-scroll">
                        <table class="data-table" id="ipsTable">
                            <thead>
                                <tr>
                                    <th>排名</th>
                                    <th>IP地址</th>
                                    <th>请求数</th>
                                    <th>占比</th>
                                </tr>
                            </thead>
                            <tbody></tbody>
                        </table>
                    </div>
                </div>
            </div>
            
            <div id="tab-urls" class="tab-content">
                <div class="card">
                    <div class="card-title">访问最多的URL</div>
                    <div class="table-scroll">
                        <table class="data-table" id="urlsTable">
                            <thead>
                                <tr>
                                    <th>排名</th>
                                    <th>URL</th>
                                    <th>请求数</th>
                                </tr>
                            </thead>
                            <tbody></tbody>
                        </table>
                    </div>
                </div>
            </div>
            
            <div id="tab-domains" class="tab-content">
                <div class="card">
                    <div class="card-title">域名请求统计</div>
                    <div class="table-scroll">
                        <table class="data-table" id="domainsTable">
                            <thead>
                                <tr>
                                    <th>排名</th>
                                    <th>域名</th>
                                    <th>请求数</th>
                                    <th>占比</th>
                                </tr>
                            </thead>
                            <tbody></tbody>
                        </table>
                    </div>
                </div>
            </div>
            
            <div id="tab-agents" class="tab-content">
                <div class="card">
                    <div class="card-title">User-Agent 统计</div>
                    <div class="table-scroll">
                        <table class="data-table" id="agentsTable">
                            <thead>
                                <tr>
                                    <th>排名</th>
                                    <th>User-Agent</th>
                                    <th>请求数</th>
                                    <th>占比</th>
                                </tr>
                            </thead>
                            <tbody></tbody>
                        </table>
                    </div>
                </div>
            </div>
            
            <div id="tab-status" class="tab-content">
                <div class="two-column">
                    <div class="card">
                        <div class="card-title">状态码分布</div>
                        <div style="height: 300px;">
                            <canvas id="statusChart"></canvas>
                        </div>
                    </div>
                    <div class="card">
                        <div class="card-title">状态码详情</div>
                        <div class="table-scroll">
                            <table class="data-table" id="statusTable">
                                <thead>
                                    <tr>
                                        <th>状态码</th>
                                        <th>描述</th>
                                        <th>请求数</th>
                                        <th>占比</th>
                                    </tr>
                                </thead>
                                <tbody></tbody>
                            </table>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        
        <div id="emptyState" class="card empty-state">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
                <path d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
            </svg>
            <h3>选择日志文件开始分析</h3>
            <p>从上方下拉菜单中选择要分析的日志文件</p>
        </div>
    </div>
    
    <!-- IP详情弹窗 -->
    <div id="ipModal" class="modal">
        <div class="modal-content">
            <div class="modal-header">
                <h3 id="modalTitle">IP详情</h3>
                <button class="close-btn" onclick="closeModal()">&times;</button>
            </div>
            <div class="modal-body" id="modalBody"></div>
        </div>
    </div>
    
    <script>
        let mainChart = null;
        let statusChart = null;
        let currentData = null;
        let visibleDatasets = {};
        
        const STATUS_DESCRIPTIONS = {
            '200': '成功',
            '201': '已创建',
            '204': '无内容',
            '301': '永久重定向',
            '302': '临时重定向',
            '304': '未修改',
            '400': '错误请求',
            '401': '未授权',
            '403': '禁止访问',
            '404': '未找到',
            '429': '请求过多',
            '500': '服务器错误',
            '502': '网关错误',
            '503': '服务不可用',
            '504': '网关超时'
        };
        
        const COLORS = {
            total: '#3b82f6',
            ips: '#a855f7',
            '200': '#22c55e',
            '201': '#10b981',
            '204': '#14b8a6',
            '301': '#06b6d4',
            '302': '#0ea5e9',
            '304': '#6366f1',
            '400': '#f59e0b',
            '401': '#f97316',
            '403': '#fb923c',
            '404': '#eab308',
            '429': '#ef4444',
            '500': '#dc2626',
            '502': '#b91c1c',
            '503': '#991b1b',
            '504': '#7f1d1d'
        };
        
        // 主题管理
        function initTheme() {
            const savedTheme = localStorage.getItem('theme') || 'light';
            document.documentElement.setAttribute('data-theme', savedTheme);
            updateThemeIcon(savedTheme);
        }

        function toggleTheme() {
            const currentTheme = document.documentElement.getAttribute('data-theme') === 'dark' ? 'dark' : 'light';
            const newTheme = currentTheme === 'dark' ? 'light' : 'dark';
            
            document.documentElement.setAttribute('data-theme', newTheme);
            localStorage.setItem('theme', newTheme);
            updateThemeIcon(newTheme);
            
            // 重绘图表以更新颜色
            if (mainChart) renderMainChart();
            if (statusChart) renderStatusChart();
        }

        function updateThemeIcon(theme) {
            const icon = theme === 'dark' ? '☀️' : '🌙';
            const btn = document.getElementById('themeIcon');
            if(btn) btn.textContent = icon;
        }

        // 页面加载时获取日志文件列表
        document.addEventListener('DOMContentLoaded', () => {
            initTheme();
            loadLogFiles();
            updateRangeLabels();

            setRangeMode('percent', { suppressLoad: true });

            window.__timeInputsAutoFilled = { start: false, end: false };
            const startEl = document.getElementById('startTime');
            const endEl = document.getElementById('endTime');
            startEl.addEventListener('input', () => { window.__timeInputsAutoFilled.start = false; });
            endEl.addEventListener('input', () => { window.__timeInputsAutoFilled.end = false; });

            startEl.addEventListener('change', () => {
                if (getRangeMode() === 'datetime') loadFileInfo();
            });
            endEl.addEventListener('change', () => {
                if (getRangeMode() === 'datetime') loadFileInfo();
            });
        });
        
        async function loadLogFiles() {
            try {
                const response = await fetch('?action=list_logs');
                const files = await response.json();
                
                const select = document.getElementById('logFile');
                select.innerHTML = '<option value="">-- 请选择日志文件 --</option>';
                
                files.forEach(file => {
                    const option = document.createElement('option');
                    option.value = file.name;
                    option.textContent = `${file.name} (${file.size_human})`;
                    select.appendChild(option);
                });
            } catch (e) {
                console.error('加载文件列表失败:', e);
            }
        }
        
        async function loadFileInfo() {
            const filename = document.getElementById('logFile').value;
            const infoDiv = document.getElementById('fileInfo');
            const rangeParams = getRangeQueryParams();
            const startTime = document.getElementById('startTime')?.value;
            const endTime = document.getElementById('endTime')?.value;
            
            if (!filename) {
                infoDiv.style.display = 'none';
                return;
            }

            const requestId = (window.__fileInfoRequestId = (window.__fileInfoRequestId || 0) + 1);
            infoDiv.innerHTML = `<p style="font-size: 0.9rem; color: var(--text-secondary);">正在计算区间信息...</p>`;
            infoDiv.style.display = 'block';
            
            try {
                let url = `?action=file_info&file=${encodeURIComponent(filename)}${rangeParams}`;
                if (getRangeMode() === 'datetime') {
                    if (startTime) url += `&start=${encodeURIComponent(startTime.replace('T', ' '))}`;
                    if (endTime) url += `&end=${encodeURIComponent(endTime.replace('T', ' '))}`;
                }
                const response = await fetch(url);
                const info = await response.json();

                if (requestId !== window.__fileInfoRequestId) {
                    return;
                }
                
                if (info.error) {
                    infoDiv.innerHTML = `<p style="color: var(--accent-red);">错误: ${info.error}</p>`;
                    infoDiv.style.display = 'block';
                    return;
                }
                
                // 设置建议的统计间隔
                if (info.suggested_interval) {
                    document.getElementById('interval').value = info.suggested_interval;
                }

                // 大文件默认只分析“末尾约 50 万行”（按预估行数换算为百分比区间），避免全量扫描过慢
                // 仅在百分比模式 + 用户尚未自定义区间时应用
                if (getRangeMode() === 'percent') {
                    const presetEl = document.getElementById('rangePreset');
                    const startEl = document.getElementById('rangeStart');
                    const endEl = document.getElementById('rangeEnd');
                    const preset = presetEl ? presetEl.value : 'full';
                    const estimated = Number(info.estimated_lines || 0);
                    const alreadyApplied = window.__adaptiveTailAppliedFor === filename;

                    const startIsDefault = startEl && String(startEl.value) === '0';
                    const endIsDefault = endEl && String(endEl.value) === '100';

                    if (estimated > 0 && estimated > 500000 && preset === 'full' && startIsDefault && endIsDefault && !alreadyApplied) {
                        const targetTailLines = 500000;
                        const tailPercent = (targetTailLines / estimated) * 100;
                        const rangeStart = Math.max(0, 100 - tailPercent);
                        const rangeEnd = 100;

                        window.__adaptiveTailAppliedFor = filename;

                        if (presetEl) presetEl.value = 'custom';
                        if (startEl) startEl.value = String(Number(rangeStart).toFixed(1));
                        if (endEl) endEl.value = String(Number(rangeEnd).toFixed(1));
                        updateRangeLabels();
                        loadFileInfo();
                        return;
                    }
                }
                
                // 设置时间范围
                if (info.time_span) {
                    const startDate = parseLogDate(info.time_span.start);
                    const endDate = parseLogDate(info.time_span.end);
                    
                    if (getRangeMode() === 'datetime' && startDate && (!document.getElementById('startTime').value || window.__timeInputsAutoFilled?.start)) {
                        document.getElementById('startTime').value = formatDateTimeLocal(startDate);
                        window.__timeInputsAutoFilled.start = true;
                    }
                    if (getRangeMode() === 'datetime' && endDate && (!document.getElementById('endTime').value || window.__timeInputsAutoFilled?.end)) {
                        document.getElementById('endTime').value = formatDateTimeLocal(endDate);
                        window.__timeInputsAutoFilled.end = true;
                    }
                }
                
                infoDiv.innerHTML = `
                    <div class="file-info-grid">
                        <div class="file-info-item">
                            <div class="file-info-value">${info.size_human}</div>
                            <div class="file-info-label">文件大小</div>
                        </div>
                        <div class="file-info-item">
                            <div class="file-info-value">${formatNumber(info.estimated_lines)}</div>
                            <div class="file-info-label">预估行数</div>
                        </div>
                        <div class="file-info-item">
                            <div class="file-info-value">${info.time_span?.human || '-'}</div>
                            <div class="file-info-label">时间跨度</div>
                        </div>
                        <div class="file-info-item">
                            <div class="file-info-value">${info.suggested_interval}秒</div>
                            <div class="file-info-label">建议间隔</div>
                        </div>
                    </div>
                    ${info.time_span ? `
                    <p style="margin-top: 10px; font-size: 0.85rem; color: var(--text-secondary);">
                        时间范围: ${info.time_span.start} 至 ${info.time_span.end}
                    </p>
                    ` : ''}
                `;
                infoDiv.style.display = 'block';
            } catch (e) {
                console.error('获取文件信息失败:', e);
                if (requestId !== window.__fileInfoRequestId) {
                    return;
                }
                infoDiv.innerHTML = `<p style="color: var(--accent-red);">获取文件信息失败，请查看控制台</p>`;
                infoDiv.style.display = 'block';
            }
        }
        
        function parseLogDate(dateStr) {
            // 解析格式: 10/Jan/2026:18:11:46 +0800
            const match = dateStr.match(/(\d+)\/(\w+)\/(\d+):(\d+):(\d+):(\d+)/);
            if (!match) return null;
            
            const months = {
                'Jan': 0, 'Feb': 1, 'Mar': 2, 'Apr': 3, 'May': 4, 'Jun': 5,
                'Jul': 6, 'Aug': 7, 'Sep': 8, 'Oct': 9, 'Nov': 10, 'Dec': 11
            };
            
            return new Date(
                parseInt(match[3]),
                months[match[2]],
                parseInt(match[1]),
                parseInt(match[4]),
                parseInt(match[5]),
                parseInt(match[6])
            );
        }
        
        function formatDateTimeLocal(date) {
            const pad = n => n.toString().padStart(2, '0');
            return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
        }
        
        function formatNumber(num) {
            if (num >= 1000000) return (num / 1000000).toFixed(1) + 'M';
            if (num >= 1000) return (num / 1000).toFixed(1) + 'K';
            return num.toString();
        }
        
        function resetFilterState(opts = {}) {
            const keepRangeMode = !!opts.keepRangeMode;
            const currentMode = getRangeMode();

            document.getElementById('startTime').value = '';
            document.getElementById('endTime').value = '';
            document.getElementById('interval').value = '60';
            document.getElementById('rangePreset').value = 'full';
            document.getElementById('rangeStart').value = '0';
            document.getElementById('rangeEnd').value = '100';
            updateRangeLabels();

            // 不要在切换文件时改变“区间选择模式”；仅在用户显式重置时才回到 percent
            if (keepRangeMode) {
                setRangeMode(currentMode, { suppressLoad: true });
            } else {
                setRangeMode('percent', { suppressLoad: true });
            }

            const hasFile = !!document.getElementById('logFile')?.value;
            if (hasFile) loadFileInfo();
        }

        function clearFilters() {
            resetFilterState({ keepRangeMode: false });
        }

        function onLogFileChange() {
            // 切换文件时自动重置筛选（日期/区间/间隔），但不改变“日期选择模式”
            resetFilterState({ keepRangeMode: true });
        }

        function updateRangeLabels() {
            const s = Number(document.getElementById('rangeStart').value || 0);
            const e = Number(document.getElementById('rangeEnd').value || 100);
            document.getElementById('rangeStartLabel').innerText = `${s.toFixed(1)}%`;
            document.getElementById('rangeEndLabel').innerText = `${e.toFixed(1)}%`;
        }

        function onRangeInput(which) {
            const startEl = document.getElementById('rangeStart');
            const endEl = document.getElementById('rangeEnd');
            let s = Number(startEl.value);
            let e = Number(endEl.value);
            const minSpan = 1;

            if (e - s < minSpan) {
                if (which === 'end') {
                    // 用户拖动右端点：推左端点
                    s = Math.max(0, e - minSpan);
                    startEl.value = String(s);
                } else {
                    // 用户拖动左端点（或未知）：推右端点
                    e = Math.min(100, s + minSpan);
                    endEl.value = String(e);
                }
            }
            document.getElementById('rangePreset').value = 'custom';
            updateRangeLabels();
            loadFileInfo();
        }

        function applyRangePreset() {
            const preset = document.getElementById('rangePreset').value;
            const startEl = document.getElementById('rangeStart');
            const endEl = document.getElementById('rangeEnd');

            if (preset === 'full') {
                startEl.value = '0';
                endEl.value = '100';
            } else if (preset === 'tail50') {
                startEl.value = '50';
                endEl.value = '100';
            } else if (preset === 'tail20') {
                startEl.value = '80';
                endEl.value = '100';
            } else if (preset === 'tail10') {
                startEl.value = '90';
                endEl.value = '100';
            } else if (preset === 'tail5') {
                startEl.value = '95';
                endEl.value = '100';
            }

            // 强制最小跨度 1%
            const minSpan = 1;
            let s = Number(startEl.value);
            let e = Number(endEl.value);
            if (e - s < minSpan) {
                e = Math.min(100, s + minSpan);
                endEl.value = String(e);
            }

            updateRangeLabels();
            loadFileInfo();
        }

        function getRangeQueryParams() {
            if (getRangeMode() !== 'percent') return '';
            const s = Number(document.getElementById('rangeStart')?.value || 0);
            const e = Number(document.getElementById('rangeEnd')?.value || 100);
            return `&range_start=${encodeURIComponent(s)}&range_end=${encodeURIComponent(e)}`;
        }

        function getRangeMode() {
            return document.getElementById('rangeMode')?.value || 'percent';
        }

        function onRangeModeChange() {
            setRangeMode(getRangeMode());
        }

        function setRangeMode(mode, opts = {}) {
            const suppressLoad = !!opts.suppressLoad;
            const normalized = mode === 'datetime' ? 'datetime' : 'percent';
            const select = document.getElementById('rangeMode');
            const percentGroup = document.getElementById('percentRangeGroup');
            const dateTimeGroup = document.getElementById('dateTimeRangeGroup');
            const startEl = document.getElementById('startTime');
            const endEl = document.getElementById('endTime');
            const rangePreset = document.getElementById('rangePreset');
            const rangeStart = document.getElementById('rangeStart');
            const rangeEnd = document.getElementById('rangeEnd');

            if (select) select.value = normalized;

            if (normalized === 'datetime') {
                if (percentGroup) percentGroup.style.display = 'none';
                if (dateTimeGroup) dateTimeGroup.style.display = '';
                if (startEl) startEl.disabled = false;
                if (endEl) endEl.disabled = false;
                if (rangePreset) rangePreset.disabled = true;
                if (rangeStart) rangeStart.disabled = true;
                if (rangeEnd) rangeEnd.disabled = true;
            } else {
                if (percentGroup) percentGroup.style.display = '';
                if (dateTimeGroup) dateTimeGroup.style.display = 'none';
                if (startEl) startEl.disabled = true;
                if (endEl) endEl.disabled = true;
                if (rangePreset) rangePreset.disabled = false;
                if (rangeStart) rangeStart.disabled = false;
                if (rangeEnd) rangeEnd.disabled = false;
                if (startEl) startEl.value = '';
                if (endEl) endEl.value = '';
            }

            if (!suppressLoad) {
                loadFileInfo();
            }
        }
        
        async function analyze() {
            const filename = document.getElementById('logFile').value;
            if (!filename) {
                alert('请先选择日志文件');
                return;
            }
            
            const interval = document.getElementById('interval').value;
            const startTime = document.getElementById('startTime').value;
            const endTime = document.getElementById('endTime').value;
            const rangeParams = getRangeQueryParams();
            
            document.getElementById('loadingIndicator').style.display = 'flex';
            document.getElementById('resultsSection').style.display = 'none';
            document.getElementById('emptyState').style.display = 'none';
            document.getElementById('analyzeBtn').disabled = true;
            
            try {
                let url = `?action=analyze&file=${encodeURIComponent(filename)}&interval=${interval}${rangeParams}`;
                if (getRangeMode() === 'datetime') {
                    if (startTime) url += `&start=${encodeURIComponent(startTime.replace('T', ' '))}`;
                    if (endTime) url += `&end=${encodeURIComponent(endTime.replace('T', ' '))}`;
                }
                
                const response = await fetch(url);
                currentData = await response.json();
                
                if (currentData.error) {
                    alert('分析失败: ' + currentData.error);
                    return;
                }
                
                renderResults();
            } catch (e) {
                console.error('分析失败:', e);
                alert('分析失败，请查看控制台');
            } finally {
                document.getElementById('loadingIndicator').style.display = 'none';
                document.getElementById('analyzeBtn').disabled = false;
            }
        }
        
        function renderResults() {
            document.getElementById('resultsSection').style.display = 'block';
            document.getElementById('emptyState').style.display = 'none';
            
            renderStats();
            renderMainChart();
            renderTables();
            renderStatusChart();
        }
        
        function renderStats() {
            const data = currentData.summary;
            const status = data.status_breakdown;
            
            const successCount = (status['200'] || 0) + (status['201'] || 0) + (status['204'] || 0);
            const redirectCount = (status['301'] || 0) + (status['302'] || 0) + (status['304'] || 0);
            const clientErrorCount = Object.entries(status)
                .filter(([k]) => k.startsWith('4'))
                .reduce((sum, [, v]) => sum + v, 0);
            const serverErrorCount = Object.entries(status)
                .filter(([k]) => k.startsWith('5'))
                .reduce((sum, [, v]) => sum + v, 0);
            
            document.getElementById('statsGrid').innerHTML = `
                <div class="stat-card blue">
                    <div class="stat-value">${formatNumber(data.total_requests)}</div>
                    <div class="stat-label">总请求数</div>
                </div>
                <div class="stat-card purple">
                    <div class="stat-value">${formatNumber(data.unique_ips)}</div>
                    <div class="stat-label">独立IP</div>
                </div>
                <div class="stat-card green">
                    <div class="stat-value">${formatNumber(successCount)}</div>
                    <div class="stat-label">成功 (2xx)</div>
                </div>
                <div class="stat-card yellow">
                    <div class="stat-value">${formatNumber(clientErrorCount)}</div>
                    <div class="stat-label">客户端错误 (4xx)</div>
                </div>
                <div class="stat-card red">
                    <div class="stat-value">${formatNumber(serverErrorCount)}</div>
                    <div class="stat-label">服务器错误 (5xx)</div>
                </div>
            `;
        }
        
        function renderMainChart() {
            const ctx = document.getElementById('mainChart').getContext('2d');
            
            if (mainChart) {
                mainChart.destroy();
            }
            
            const labels = currentData.timeline.map(d => d.time);
            const datasets = [];
            
            // 初始化可见状态
            visibleDatasets = { total: true, ips: true };
            currentData.status_codes.forEach(code => {
                // 默认显示 200 和 429
                visibleDatasets['status_' + code] = (String(code) === '200' || String(code) === '429');
            });
            
            // 总请求数
            datasets.push({
                label: '总请求数',
                data: currentData.timeline.map(d => d.total),
                borderColor: COLORS.total,
                backgroundColor: COLORS.total + '20',
                borderWidth: 1.5,
                fill: false,
                tension: 0.3,
                yAxisID: 'y',
                pointRadius: 1,
                pointHoverRadius: 4
            });
            
            // 独立IP数
            datasets.push({
                label: '独立IP数',
                data: currentData.timeline.map(d => d.unique_ips),
                borderColor: COLORS.ips,
                backgroundColor: COLORS.ips + '20',
                borderWidth: 1.5,
                fill: false,
                tension: 0.3,
                yAxisID: 'y',
                pointRadius: 1,
                pointHoverRadius: 4
            });
            
            // 状态码曲线
            currentData.status_codes.forEach(code => {
                const shouldShow = (String(code) === '200' || String(code) === '429');
                datasets.push({
                    label: `状态码 ${code}`,
                    data: currentData.timeline.map(d => d['status_' + code] || 0),
                    borderColor: COLORS[code] || '#888',
                    backgroundColor: (COLORS[code] || '#888') + '20',
                    borderWidth: 1.5,
                    fill: false,
                    tension: 0.3,
                    yAxisID: 'y',
                    pointRadius: 1,
                    pointHoverRadius: 3,
                    hidden: !shouldShow
                });
            });
            
            mainChart = new Chart(ctx, {
                type: 'line',
                data: { labels, datasets },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    interaction: {
                        mode: 'index',
                        intersect: false
                    },
                    onClick: (event, elements) => {
                        if (elements.length > 0) {
                            const index = elements[0].index;
                            const point = currentData.timeline[index];
                            showIPDetails(point.timestamp);
                        }
                    },
                    scales: {
                        x: {
                            ticks: {
                                color: getComputedStyle(document.documentElement).getPropertyValue('--chart-text-color').trim()
                            },
                            grid: {
                                color: getComputedStyle(document.documentElement).getPropertyValue('--chart-grid-color').trim()
                            }
                        },
                        y: {
                            type: 'linear',
                            position: 'left',
                            title: {
                                display: true,
                                text: '请求数',
                                color: getComputedStyle(document.documentElement).getPropertyValue('--chart-text-color').trim()
                            },
                            ticks: {
                                color: getComputedStyle(document.documentElement).getPropertyValue('--chart-text-color').trim()
                            },
                            grid: {
                                color: getComputedStyle(document.documentElement).getPropertyValue('--chart-grid-color').trim()
                            }
                        }
                    },
                    plugins: {
                        legend: {
                            display: false
                        },
                        tooltip: {
                            backgroundColor: '#1e293b',
                            titleColor: '#f1f5f9',
                            bodyColor: '#94a3b8',
                            borderColor: '#475569',
                            borderWidth: 1,
                            padding: 12,
                            displayColors: true,
                            callbacks: {
                                afterBody: function(tooltipItems) {
                                    return '点击查看该时间段IP详情';
                                }
                            }
                        }
                    }
                }
            });
            
            renderLegend();
        }
        
        function renderLegend() {
            const container = document.getElementById('legendContainer');
            container.innerHTML = '';
            
            // 总请求数
            addLegendItem(container, 'total', '总请求数', COLORS.total, true);
            
            // 独立IP数
            addLegendItem(container, 'ips', '独立IP数', COLORS.ips, true);
            
            // 状态码
            currentData.status_codes.forEach(code => {
                const color = COLORS[code] || '#888';
                const isVisible = (String(code) === '200' || String(code) === '429');
                addLegendItem(container, 'status_' + code, `${code} ${STATUS_DESCRIPTIONS[code] || ''}`, color, isVisible);
            });
        }
        
        function addLegendItem(container, key, label, color, visible) {
            const item = document.createElement('div');
            item.className = 'legend-item' + (visible ? '' : ' disabled');
            item.innerHTML = `
                <div class="legend-color" style="background: ${color}"></div>
                <span>${label}</span>
            `;
            item.onclick = () => toggleDataset(key, item);
            container.appendChild(item);
        }
        
        function toggleDataset(key, element) {
            // 根据 key 找到对应的 label prefix
            let targetLabelPrefix = '';
            if (key === 'total') targetLabelPrefix = '总请求数';
            else if (key === 'ips') targetLabelPrefix = '独立IP数';
            else if (key.startsWith('status_')) {
                const code = key.replace('status_', '');
                targetLabelPrefix = `状态码 ${code}`;
            }

            // 在 datasets 中查找匹配的 index
            const datasetIndex = mainChart.data.datasets.findIndex(ds => ds.label.startsWith(targetLabelPrefix));
            
            if (datasetIndex !== -1) {
                const dataset = mainChart.data.datasets[datasetIndex];
                // 切换 hidden 状态：Chart.js 中 hidden=true 是隐藏，undefined/false 是显示
                // 注意：如果之前未设置 hidden，它默认为 undefined (显示)
                // 这里我们直接反转当前状态，如果没有 hidden 属性，视为 false (显示) -> 设为 true (隐藏)
                const isHidden = dataset.hidden === true;
                dataset.hidden = !isHidden;
                
                element.classList.toggle('disabled', dataset.hidden);
                mainChart.update();
            } else {
                console.warn('Dataset not found for key:', key);
            }
        }
        
        function renderTables() {
            // IP表格
            const ipsBody = document.querySelector('#ipsTable tbody');
            ipsBody.innerHTML = '';
            let rank = 1;
            for (const [ip, count] of Object.entries(currentData.top_ips)) {
                const percent = (count / currentData.summary.total_requests * 100).toFixed(2);
                ipsBody.innerHTML += `
                    <tr>
                        <td>${rank++}</td>
                        <td><code>${ip}</code></td>
                        <td>${formatNumber(count)}</td>
                        <td>${percent}%</td>
                    </tr>
                `;
            }
            
            // URL表格
            const urlsBody = document.querySelector('#urlsTable tbody');
            urlsBody.innerHTML = '';
            rank = 1;
            for (const [url, count] of Object.entries(currentData.top_urls)) {
                urlsBody.innerHTML += `
                    <tr>
                        <td>${rank++}</td>
                        <td class="url-cell" title="${escapeHtml(url)}">${escapeHtml(url)}</td>
                        <td>${formatNumber(count)}</td>
                    </tr>
                `;
            }
            
            // 域名表格
            const domainsBody = document.querySelector('#domainsTable tbody');
            domainsBody.innerHTML = '';
            rank = 1;
            for (const [domain, count] of Object.entries(currentData.domains)) {
                const percent = (count / currentData.summary.total_requests * 100).toFixed(2);
                domainsBody.innerHTML += `
                    <tr>
                        <td>${rank++}</td>
                        <td>${escapeHtml(domain)}</td>
                        <td>${formatNumber(count)}</td>
                        <td>${percent}%</td>
                    </tr>
                `;
            }
            
            // UA表格
            const agentsBody = document.querySelector('#agentsTable tbody');
            agentsBody.innerHTML = '';
            rank = 1;
            for (const [ua, count] of Object.entries(currentData.user_agents)) {
                const percent = (count / currentData.summary.total_requests * 100).toFixed(2);
                const badgeClass = ua.toLowerCase().includes('bot') ? 'badge-warning' : 'badge-info';
                agentsBody.innerHTML += `
                    <tr>
                        <td>${rank++}</td>
                        <td><span class="badge ${badgeClass}">${escapeHtml(ua)}</span></td>
                        <td>${formatNumber(count)}</td>
                        <td>${percent}%</td>
                    </tr>
                `;
            }
            
            // 状态码表格
            const statusBody = document.querySelector('#statusTable tbody');
            statusBody.innerHTML = '';
            const sortedStatus = Object.entries(currentData.summary.status_breakdown)
                .sort((a, b) => b[1] - a[1]);
            for (const [code, count] of sortedStatus) {
                const percent = (count / currentData.summary.total_requests * 100).toFixed(2);
                let badgeClass = 'badge-info';
                if (code.startsWith('2')) badgeClass = 'badge-success';
                else if (code.startsWith('4')) badgeClass = 'badge-warning';
                else if (code.startsWith('5')) badgeClass = 'badge-error';
                
                statusBody.innerHTML += `
                    <tr>
                        <td><span class="badge ${badgeClass}">${code}</span></td>
                        <td>${STATUS_DESCRIPTIONS[code] || '未知'}</td>
                        <td>${formatNumber(count)}</td>
                        <td>${percent}%</td>
                    </tr>
                `;
            }
        }
        
        function renderStatusChart() {
            const ctx = document.getElementById('statusChart').getContext('2d');
            
            if (statusChart) {
                statusChart.destroy();
            }
            
            const statusData = currentData.summary.status_breakdown;
            const labels = Object.keys(statusData);
            const values = Object.values(statusData);
            const colors = labels.map(code => COLORS[code] || '#888');
            
            statusChart = new Chart(ctx, {
                type: 'doughnut',
                data: {
                    labels: labels.map(code => `${code} ${STATUS_DESCRIPTIONS[code] || ''}`),
                    datasets: [{
                        data: values,
                        backgroundColor: colors,
                        borderColor: '#1e293b',
                        borderWidth: 2
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: {
                            position: 'right',
                            labels: {
                                color: '#94a3b8',
                                padding: 10,
                                usePointStyle: true
                            }
                        }
                    }
                }
            });
        }
        
        function switchTab(tabName) {
            document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
            document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
            
            document.querySelector(`.tab[onclick="switchTab('${tabName}')"]`).classList.add('active');
            document.getElementById('tab-' + tabName).classList.add('active');
        }
        
        async function showIPDetails(timestamp) {
            const modal = document.getElementById('ipModal');
            const body = document.getElementById('modalBody');
            const filename = document.getElementById('logFile').value;
            const interval = document.getElementById('interval').value;
            const rangeParams = getRangeQueryParams();

            modal.classList.add('active');
            body.innerHTML = '<div class="loading" style="padding: 20px;"><div class="spinner" style="width: 24px; height: 24px; margin-right: 10px;"></div><span>正在加载...</span></div>';

            try {
                const response = await fetch(
                    `?action=get_ips&file=${encodeURIComponent(filename)}&timestamp=${timestamp}&interval=${interval}${rangeParams}`
                );
                const data = await response.json();

                if (data.error) {
                    body.innerHTML = `<p style="color: var(--accent-red);">获取IP详情失败: ${data.error}</p>`;
                    return;
                }

                const uniqueIPCount = Object.keys(data.ips || {}).length;
                const timeStart = data.time_start || '';
                const timeEnd = data.time_end || '';

                document.getElementById('modalTitle').innerText = `IP详情: ${timeStart} - ${timeEnd}`;

                body.innerHTML = `
                    <div style="display:flex; justify-content: space-between; align-items:center; margin-bottom: 12px; gap: 10px; flex-wrap: wrap;">
                        <div style="font-size: 0.9rem; color: var(--text-secondary);">独立IP: <b style="color: var(--text-primary);">${uniqueIPCount}</b></div>
                        <button class="btn-secondary" style="font-size: 0.8rem; padding: 4px 10px;" onclick="exportIPData()">
                            <span>⬇️</span> 导出JSON
                        </button>
                    </div>
                `;

                if (uniqueIPCount === 0) {
                    body.innerHTML += '<div class="empty-state" style="padding: 20px;">该时间段无数据</div>';
                    return;
                }

                window.ipModalSortState = window.ipModalSortState || {
                    field: 'count',
                    order: 'desc',
                    statusCode: ''
                };
                window.currentIPDataRaw = data;
                renderIPModalList(data);
            } catch (e) {
                console.error(e);
                body.innerHTML = '<p style="color: var(--accent-red);">加载失败</p>';
            }
        }

        function renderIPModalList(data) {
            const body = document.getElementById('modalBody');
            const sortState = window.ipModalSortState || { field: 'count', order: 'desc', statusCode: '' };

            const statusCodes = new Set();
            for (const info of Object.values(data.ips || {})) {
                for (const code of Object.keys(info.statuses || {})) {
                    statusCodes.add(String(code));
                }
            }
            const statusCodeList = Array.from(statusCodes).sort((a, b) => Number(a) - Number(b));

            if (sortState.field === 'status' && !sortState.statusCode) {
                sortState.statusCode = statusCodeList[0] || '';
            }

            const items = Object.entries(data.ips || {}).map(([ip, info]) => ({ ip, info }));
            items.sort((a, b) => {
                let va;
                let vb;

                if (sortState.field === 'ip') {
                    va = a.ip;
                    vb = b.ip;
                    const cmp = String(va).localeCompare(String(vb), undefined, { numeric: true, sensitivity: 'base' });
                    return sortState.order === 'asc' ? cmp : -cmp;
                }

                if (sortState.field === 'status') {
                    const code = String(sortState.statusCode || '');
                    va = Number(a.info?.statuses?.[code] || 0);
                    vb = Number(b.info?.statuses?.[code] || 0);
                } else {
                    va = Number(a.info?.count || 0);
                    vb = Number(b.info?.count || 0);
                }

                const diff = va - vb;
                return sortState.order === 'asc' ? diff : -diff;
            });

            const orderLabel = sortState.order === 'asc' ? '↑' : '↓';
            const sortValue = sortState.field === 'status' ? 'status' : sortState.field;

            let html = `
                <div style="display:flex; gap:10px; align-items:center; margin-bottom: 12px; flex-wrap: wrap;">
                    <div style="font-size: 0.85rem; color: var(--text-secondary);">排序</div>
                    <select id="ipSortField" style="padding: 6px 10px; font-size: 0.9rem;" onchange="onIPSortChange()">
                        <option value="count" ${sortValue === 'count' ? 'selected' : ''}>按请求数</option>
                        <option value="ip" ${sortValue === 'ip' ? 'selected' : ''}>按IP</option>
                        <option value="status" ${sortValue === 'status' ? 'selected' : ''}>按状态码请求数</option>
                    </select>
                    <select id="ipSortStatusCode" style="padding: 6px 10px; font-size: 0.9rem; ${sortValue === 'status' ? '' : 'display:none;'}" onchange="onIPSortChange()">
                        ${statusCodeList.map(code => `<option value="${code}" ${String(sortState.statusCode) === String(code) ? 'selected' : ''}>${code}</option>`).join('')}
                    </select>
                    <button class="btn-secondary" style="font-size: 0.85rem; padding: 6px 10px;" onclick="toggleIPSortOrder()">${orderLabel}</button>
                    <div style="margin-left:auto; font-size: 0.85rem; color: var(--text-secondary);">共 ${items.length} 个IP</div>
                </div>
                <div class="ip-list-container">
                    <div class="ip-list-header">
                        <div style="cursor:pointer;" onclick="setIPModalSort('ip')">IP地址 / 状态码分布 ${sortState.field === 'ip' ? orderLabel : ''}</div>
                        <div style="text-align: right; padding-right: 15px; cursor:pointer;" onclick="setIPModalSort('count')">请求数 ${sortState.field === 'count' ? orderLabel : ''}</div>
                        <div style="text-align: center;">展开</div>
                    </div>
            `;

            for (const { ip, info } of items) {
                const statusBadges = Object.entries(info.statuses || {})
                    .map(([code, count]) => {
                        let cls = 'badge-info';
                        if (String(code).startsWith('2')) cls = 'badge-success';
                        else if (String(code).startsWith('4')) cls = 'badge-warning';
                        else if (String(code).startsWith('5')) cls = 'badge-error';
                        const highlight = (sortState.field === 'status' && String(sortState.statusCode) === String(code))
                            ? 'border:1px solid var(--accent-blue);'
                            : '';
                        return `<span class="badge ${cls}" style="font-size: 0.75rem; margin-right: 4px; ${highlight}">${code}:${count}</span>`;
                    })
                    .join('');

                html += `
                    <div class="ip-item">
                        <div class="ip-row-main" onclick="toggleIpDetails(this)">
                            <div>
                                <div class="ip-address">${ip}</div>
                                <div style="margin-top: 4px;">${statusBadges}</div>
                            </div>
                            <div class="ip-count">${info.count}</div>
                            <div class="toggle-icon">▼</div>
                        </div>
                        <div class="ip-details">
                            <div class="detail-section">
                                <div class="detail-title">访问 URL (${info.urls.length})</div>
                                <ul class="url-list">
                                    ${info.urls.map(item => {
                                        const url = typeof item === 'string' ? item : item.url;
                                        const status = typeof item === 'string' ? '' : item.status;

                                        let badgeHtml = '';
                                        if (status) {
                                            let cls = 'badge-info';
                                            if (String(status).startsWith('2')) cls = 'badge-success';
                                            else if (String(status).startsWith('4')) cls = 'badge-warning';
                                            else if (String(status).startsWith('5')) cls = 'badge-error';
                                            badgeHtml = `<span class="badge ${cls}" style="font-size: 0.7em; margin-right: 6px; padding: 1px 5px;">${status}</span>`;
                                        }

                                        return `<li>${badgeHtml}${escapeHtml(url)}</li>`;
                                    }).join('')}
                                </ul>
                            </div>
                        </div>
                    </div>
                `;
            }

            html += '</div>';
            body.innerHTML = html;
        }

        function onIPSortChange() {
            const fieldEl = document.getElementById('ipSortField');
            const codeEl = document.getElementById('ipSortStatusCode');
            if (!fieldEl) return;

            const field = fieldEl.value;
            window.ipModalSortState = window.ipModalSortState || { field: 'count', order: 'desc', statusCode: '' };
            window.ipModalSortState.field = field;
            if (codeEl) {
                if (field === 'status') {
                    codeEl.style.display = '';
                    window.ipModalSortState.statusCode = codeEl.value || window.ipModalSortState.statusCode;
                } else {
                    codeEl.style.display = 'none';
                }
            }

            if (window.currentIPDataRaw) renderIPModalList(window.currentIPDataRaw);
        }

        function toggleIPSortOrder() {
            window.ipModalSortState = window.ipModalSortState || { field: 'count', order: 'desc', statusCode: '' };
            window.ipModalSortState.order = window.ipModalSortState.order === 'asc' ? 'desc' : 'asc';
            if (window.currentIPDataRaw) renderIPModalList(window.currentIPDataRaw);
        }

        function setIPModalSort(field) {
            window.ipModalSortState = window.ipModalSortState || { field: 'count', order: 'desc', statusCode: '' };
            if (window.ipModalSortState.field === field) {
                window.ipModalSortState.order = window.ipModalSortState.order === 'asc' ? 'desc' : 'asc';
            } else {
                window.ipModalSortState.field = field;
                window.ipModalSortState.order = field === 'ip' ? 'asc' : 'desc';
            }
            if (window.currentIPDataRaw) renderIPModalList(window.currentIPDataRaw);
        }
        
        function exportIPData() {
            if (!window.currentIPData) return;
            
            const dataStr = "data:text/json;charset=utf-8," + encodeURIComponent(JSON.stringify(window.currentIPData, null, 2));
            const downloadAnchorNode = document.createElement('a');
            downloadAnchorNode.setAttribute("href", dataStr);
            console.log(window.currentIPData.time_start)
            const timestamp = window.currentIPData.time_start.replace(/[: ]/g, '_');
            downloadAnchorNode.setAttribute("download", "ip_analysis_" + timestamp + ".json");
            document.body.appendChild(downloadAnchorNode); // required for firefox
            downloadAnchorNode.click();
            downloadAnchorNode.remove();
        }
        
        function toggleIpDetails(element) {
            const item = element.parentElement;
            item.classList.toggle('active');
        }
        
        function closeModal() {
            document.getElementById('ipModal').classList.remove('active');
        }
        
        function escapeHtml(str) {
            const div = document.createElement('div');
            div.textContent = str;
            return div.innerHTML;
        }
        
        // 点击模态框外部关闭
        document.getElementById('ipModal').addEventListener('click', function(e) {
            if (e.target === this) {
                closeModal();
            }
        });
        
        // ESC键关闭模态框
        document.addEventListener('keydown', function(e) {
            if (e.key === 'Escape') {
                closeModal();
            }
        });
        function toggleFullscreen() {
            const card = document.getElementById('chartCard');
            const icon = document.getElementById('fsIcon');
            const isFullscreen = card.classList.toggle('fullscreen-mode');
            
            if (isFullscreen) {
                icon.textContent = '✖';
                document.body.style.overflow = 'hidden';
            } else {
                icon.textContent = '⛶';
                document.body.style.overflow = '';
            }
            
            // 触发 resize 事件让 chart.js 重新调整大小
            window.dispatchEvent(new Event('resize'));
        }
        
        // ESC退出全屏
        document.addEventListener('keydown', function(e) {
            if (e.key === 'Escape') {
                const card = document.getElementById('chartCard');
                if (card.classList.contains('fullscreen-mode')) {
                    toggleFullscreen();
                }
            }
        });
    </script>
</body>
</html>
