import {
  Download,
  FileJson,
  Gauge,
  History,
  ScrollText,
  Upload,
  Wand2,
} from "lucide-react";

type Props = {
  onNotify: (message: string) => void;
};

export default function Advanced({ onNotify }: Props) {
  return (
    <div className="advanced-page">
      <header className="page-head">
        <span className="eyebrow">ADVANCED</span>
        <h1>高级</h1>
        <p>低频能力集中在这里：配置向导、导入导出、历史审计与运行参数。</p>
      </header>

      <div className="advanced-grid">
        <section className="panel">
          <div className="panel-head">
            <Wand2 size={17} />
            <div>
              <h2>域名配置向导</h2>
              <p>DNS → 等激活 → 邮箱 → SSL → 安全 / 加速</p>
            </div>
          </div>
          <div className="chip-row">
            {["DNS", "等激活", "邮箱", "SSL", "安全", "加速"].map((step) => (
              <span className="step-chip" key={step}>
                {step}
              </span>
            ))}
          </div>
          <button className="button" onClick={() => onNotify("打开 provision 向导（原型）")}>
            打开配置向导
          </button>
        </section>

        <section className="panel">
          <div className="panel-head">
            <FileJson size={17} />
            <div>
              <h2>导入 / 导出</h2>
              <p>JSON 记录导入、zone 导出与变更前快照</p>
            </div>
          </div>
          <div className="button-row">
            <button className="button ghost" onClick={() => onNotify("导入记录（原型）")}>
              <Upload size={15} /> 导入记录
            </button>
            <button className="button ghost" onClick={() => onNotify("导出记录（原型）")}>
              <Download size={15} /> 导出记录
            </button>
            <button className="button ghost" onClick={() => onNotify("导出 zone CSV（原型）")}>
              导出 zone CSV
            </button>
          </div>
        </section>

        <section className="panel">
          <div className="panel-head">
            <Upload size={17} />
            <div>
              <h2>白名单 / 重跑清单</h2>
              <p>上传后只作用于本次范围，不写入账号配置</p>
            </div>
          </div>
          <div className="drop-row">
            <div className="drop-zone">
              <span>白名单 .txt / .csv</span>
              <button className="button ghost" onClick={() => onNotify("选择白名单文件（原型）")}>
                选择文件
              </button>
            </div>
            <div className="drop-zone">
              <span>失败清单 .csv</span>
              <button className="button ghost" onClick={() => onNotify("选择重跑清单（原型）")}>
                选择文件
              </button>
            </div>
          </div>
        </section>

        <section className="panel wide">
          <div className="panel-head">
            <History size={17} />
            <div>
              <h2>历史与审计</h2>
              <p>终态任务与单条写入记录，以表格展示，不再直接展示 JSON</p>
            </div>
          </div>
          <div className="mini-table">
            <div className="mini-head">
              <span>时间</span>
              <span>类型</span>
              <span>账号</span>
              <span>结果</span>
            </div>
            <div className="mini-row">
              <span>14:32</span>
              <span>preview · update</span>
              <span>cf00</span>
              <span className="status-pill running">running</span>
            </div>
            <div className="mini-row">
              <span>13:58</span>
              <span>execute · update</span>
              <span>cf00</span>
              <span className="status-pill failed">failed</span>
            </div>
            <div className="mini-row">
              <span>11:20</span>
              <span>execute · delete_wildcard</span>
              <span>cf01</span>
              <span className="status-pill done">done</span>
            </div>
          </div>
        </section>

        <section className="panel">
          <div className="panel-head">
            <Gauge size={17} />
            <div>
              <h2>运行参数</h2>
              <p>默认 eco；显式值覆盖档位</p>
            </div>
          </div>
          <div className="form-grid">
            <label className="field">
              <span className="field-label">速度档位</span>
              <select defaultValue="eco">
                <option value="eco">eco</option>
                <option value="balanced">balanced</option>
                <option value="fast">fast</option>
                <option value="turbo">turbo</option>
              </select>
            </label>
            <label className="field">
              <span className="field-label">账号并发</span>
              <input type="number" defaultValue={3} min={1} max={20} />
            </label>
            <label className="field">
              <span className="field-label">请求间隔</span>
              <input type="number" defaultValue={0.5} step={0.1} min={0} />
            </label>
            <label className="field">
              <span className="field-label">最大重试</span>
              <input type="number" defaultValue={5} min={0} />
            </label>
          </div>
        </section>

        <section className="panel">
          <div className="panel-head">
            <ScrollText size={17} />
            <div>
              <h2>原始日志</h2>
              <p>任务日志按 offset 增量拉取；默认只看摘要</p>
            </div>
          </div>
          <button className="button ghost" onClick={() => onNotify("打开原始日志（原型）")}>
            查看最近任务日志
          </button>
        </section>
      </div>
    </div>
  );
}
