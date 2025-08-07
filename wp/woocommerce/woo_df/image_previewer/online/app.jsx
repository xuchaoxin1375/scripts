import React, { useState } from "react";
import { Upload, Button, InputNumber, Select, message, Pagination, Modal } from "antd";
import { UploadOutlined, EyeOutlined } from "@ant-design/icons";

const { Option } = Select;

function getRandomSample(arr, percent) {
  const n = Math.max(1, Math.floor(arr.length * percent / 100));
  const shuffled = arr.slice().sort(() => 0.5 - Math.random());
  return shuffled.slice(0, n);
}

export default function App() {
  const [data, setData] = useState([]);
  const [field, setField] = useState("");
  const [fields, setFields] = useState([]);
  const [percent, setPercent] = useState(1);
  const [sample, setSample] = useState([]);
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(24);
  const [preview, setPreview] = useState(null);

  const handleFile = (file) => {
    window.Papa.parse(file, {
      header: true,
      skipEmptyLines: true,
      complete: (results) => {
        if (!results.data.length) {
          message.error("CSV无数据");
          return;
        }
        setData(results.data);
        setFields(Object.keys(results.data[0]));
        setField("");
        setSample([]);
        setPage(1);
        message.success("CSV读取成功，共" + results.data.length + "行");
      },
      error: () => message.error("CSV解析失败")
    });
    return False;
  };

  const handleSample = () => {
    if (!field) {
      message.error("请选择图片字段");
      return;
    }
    const urls = data.map(row => row[field]).filter(Boolean);
    if (!urls.length) {
      message.error("该字段无有效图片链接");
      return;
    }
    setSample(getRandomSample(urls, percent));
    setPage(1);
  };

  const pagedSample = sample.slice((page-1)*pageSize, page*pageSize);

  return (
    <div className="container">
      <h2>CSV图片抽样展示</h2>
      <Upload beforeUpload={handleFile} accept=".csv" showUploadList={false}>
        <Button icon={<UploadOutlined />}>上传CSV文件夹</Button>
      </Upload>
      {fields.length > 0 && (
        <div style={{marginTop:16, display:'flex', gap:16, alignItems:'center'}}>
          <span>图片字段:</span>
          <Select style={{width:180}} value={field} onChange={setField} placeholder="选择字段">
            {fields.map(f => <Option key={f} value={f}>{f}</Option>)}
          </Select>
          <span>抽样比例(%):</span>
          <InputNumber min={0.1} max={100} step={0.1} value={percent} onChange={setPercent} />
          <Button type="primary" onClick={handleSample}>抽样并展示</Button>
        </div>
      )}
      {sample.length > 0 && (
        <>
          <div style={{marginTop:24, marginBottom:8}}>共抽取 {sample.length} 张图片</div>
          <div className="image-grid">
            {pagedSample.map((url, idx) => (
              <div className="image-card" key={idx}>
                <img src={url} alt="img" onClick={()=>setPreview(url)} style={{cursor:'pointer'}} />
                <div className="url">{url}</div>
              </div>
            ))}
          </div>
          <Pagination
            style={{marginTop:24, textAlign:'center'}}
            current={page}
            pageSize={pageSize}
            total={sample.length}
            showSizeChanger
            pageSizeOptions={[12,24,48,96]}
            onChange={setPage}
            onShowSizeChange={(_, size)=>{setPageSize(size);setPage(1);}}
          />
          <Modal open={!!preview} footer={null} onCancel={()=>setPreview(null)} width={800}>
            <img src={preview} alt="预览" style={{width:'100%'}} />
          </Modal>
        </>
      )}
    </div>
  );
}
