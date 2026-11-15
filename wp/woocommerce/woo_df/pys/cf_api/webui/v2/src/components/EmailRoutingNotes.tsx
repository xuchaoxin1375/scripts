export default function EmailRoutingNotes() {
  return (
    <details className="forward-notes">
      <summary>邮箱转发注意事项（首次配置必看）</summary>
      <ul>
        <li>
          目标邮箱必须先验证：Cloudflare 会向该地址发送验证邮件，点击
          “Verify email address” 后 catch-all 才会生效；验证邮件可能进垃圾箱。
          没收到时可在 Cloudflare 控制台的 Destination Addresses 页重发。
        </li>
        <li>
          目标地址是账号级的，验证一次可复用到同账号其他域名；换一个新的目标邮箱要重新验证。
          第一个域名也不例外。新账号还要先完成 Cloudflare 账号本身的邮箱验证，它不能替代目标地址验证。
        </li>
        <li>
          域名必须在 Cloudflare DNS 且 zone 已激活；已有其他 MX（Google
          Workspace、企业邮箱等）会冲突，启用 Email Routing 会替换 MX，原邮箱可能中断。
        </li>
        <li>
          启用后会添加并锁定 MX、SPF、DKIM；已有 SPF 需要合并，DNS 生效通常
          5–15 分钟，最多 24 小时。
        </li>
        <li>
          收信测试：从另一个邮箱发到 <code>test@你的域名</code>，检查目标邮箱收件箱和垃圾箱；不要用同一个
          Gmail 发给自己，部分服务商会丢弃这种信。
        </li>
        <li>
          catch-all 会接收所有未匹配地址（包括拼错的地址）；只想收指定前缀时要在
          Cloudflare 控制台建具体 routing rule，WebUI 目前只配置 catch-all。
        </li>
        <li>
          未验证前不要切换 MX：Cloudflare 已接管邮件但没有 catch-all 时，来信会被拒绝
          （Address does not exist）。建议先“添加并验证”，再“完成配置”。
        </li>
        <li>
          API Token 需要 Email Routing Addresses / Rules / Settings
          权限；权限不足时会报 403。限制：目标地址 200 个/账号、规则 200
          条/域名、单封 25 MiB。
        </li>
      </ul>
      <p>
        官方说明：
        <a
          href="https://developers.cloudflare.com/email-service/get-started/route-emails/"
          target="_blank"
          rel="noreferrer"
        >
          Route emails
        </a>
        {" · "}
        <a
          href="https://developers.cloudflare.com/email-service/configuration/email-routing-addresses/"
          target="_blank"
          rel="noreferrer"
        >
          Destination addresses
        </a>
      </p>
    </details>
  );
}
