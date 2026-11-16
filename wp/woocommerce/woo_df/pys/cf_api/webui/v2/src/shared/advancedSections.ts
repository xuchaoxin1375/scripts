import {
  Download,
  Gauge,
  History,
  Mail,
  Search,
  Upload,
  Wand2,
} from "lucide-react";

export const ADVANCED_SECTIONS = [
  {
    key: "find",
    label: "跨账号查找",
    description: "扫描全部账号查找一个 zone；显示进度与部分结果，可取消。",
    icon: Search,
  },
  {
    key: "provision",
    label: "配置向导",
    description: "按 DNS、激活、邮箱、SSL、安全与加速分步配置；默认先预览再执行。",
    icon: Wand2,
  },
  {
    key: "email-routing",
    label: "邮箱转发",
    description: "管理账号级目标邮箱；验证后为当前域名启用路由并设置 catch-all。",
    icon: Mail,
  },
  {
    key: "transfer",
    label: "导入 / 导出",
    description: "导入记录先预检再写入；导出当前域名 JSON、zone CSV 或服务器目录任务。",
    icon: Download,
  },
  {
    key: "attachments",
    label: "范围附件",
    description: "为下一次任务附加白名单或失败重跑清单；附件只随任务使用。",
    icon: Upload,
  },
  {
    key: "history",
    label: "历史与审计",
    description: "按账号、域名与动作查看任务历史和审计日志。",
    icon: History,
  },
  {
    key: "runtime",
    label: "运行参数",
    description: "调整速度档位、限速范围与最大重试；速度与重试也用于跨账号扫描，参数只保存在本机浏览器。",
    icon: Gauge,
  },
] as const;
