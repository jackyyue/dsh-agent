# DSH Agent 首屏 Key 粘贴表单 UI 规格

## 布局

```
┌─────────────────────────────────────────┐
│                                         │
│              DSH Agent                  │
│                                         │
│  你好，我是 DSH Agent。                  │
│                                         │
│  要开始使用，需要一个免费的               │
│  DeepSeek API Key（每天有免费额度）      │
│                                         │
│  ────────────────────────────────────  │
│                                         │
│  还没有 Key？                            │
│                                         │
│  [点这里，我帮你打开注册页面]  (按钮)    │
│                                         │
│  打开后：                                │
│  1. 注册账号（手机或邮箱）               │
│  2. 进入"API Keys"页面                   │
│  3. 点"创建新密钥"                       │
│  4. 复制 sk- 开头的那串字符              │
│  5. 回到这里粘贴                         │
│                                         │
│  ────────────────────────────────────  │
│                                         │
│  已经有 Key？直接粘贴：                   │
│                                         │
│  [________________________________]  (输入框) │
│                                         │
│  [    开始    ]  (按钮)                 │
│                                         │
└─────────────────────────────────────────┘
```

## HTML 结构

```html
<div id="key-form-container">
  <div class="form-card">
    <h1>DSH Agent</h1>
    <p class="intro">你好,我是 DSH Agent。</p>
    <p class="intro">要开始使用，需要一个免费的 DeepSeek API Key（每天有免费额度）</p>
    
    <hr class="divider">
    
    <div class="no-key-section">
      <p class="section-title">还没有 Key？</p>
      <button id="btn-open-deepseek" class="btn-secondary">
        点这里，我帮你打开注册页面
      </button>
      <ol class="steps">
        <li>注册账号（手机或邮箱）</li>
        <li>进入"API Keys"页面</li>
        <li>点"创建新密钥"</li>
        <li>复制 sk- 开头的那串字符</li>
        <li>回到这里粘贴</li>
      </ol>
    </div>
    
    <hr class="divider">
    
    <div class="has-key-section">
      <p class="section-title">已经有 Key？直接粘贴：</p>
      <input 
        type="password" 
        id="input-api-key" 
        placeholder="sk-..." 
        class="key-input"
        autocomplete="off"
      >
      <p class="error-msg" id="error-msg" style="display:none;"></p>
      <button id="btn-start" class="btn-primary">开始</button>
    </div>
  </div>
</div>
```

## CSS 样式

```css
#key-form-container {
  display: flex;
  justify-content: center;
  align-items: center;
  min-height: 100vh;
  background: #f5f5f5;
  padding: 20px;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
}

.form-card {
  max-width: 520px;
  width: 100%;
  background: #fff;
  border-radius: 12px;
  padding: 40px;
  box-shadow: 0 2px 16px rgba(0,0,0,0.08);
}

h1 {
  font-size: 32px;
  font-weight: 700;
  margin-bottom: 16px;
  text-align: center;
  color: #333;
}

.intro {
  font-size: 16px;
  line-height: 1.6;
  color: #666;
  margin-bottom: 12px;
  text-align: center;
}

.divider {
  border: none;
  border-top: 1px solid #e5e5e5;
  margin: 24px 0;
}

.section-title {
  font-size: 15px;
  font-weight: 600;
  color: #333;
  margin-bottom: 12px;
}

.btn-secondary {
  width: 100%;
  padding: 12px;
  font-size: 15px;
  color: #4f46e5;
  background: #f0f0ff;
  border: 1px solid #d0d0ff;
  border-radius: 8px;
  cursor: pointer;
  margin-bottom: 16px;
}

.btn-secondary:hover {
  background: #e8e8ff;
}

.steps {
  font-size: 14px;
  color: #666;
  padding-left: 20px;
  line-height: 1.8;
}

.steps li {
  margin-bottom: 6px;
}

.key-input {
  width: 100%;
  padding: 12px;
  font-size: 15px;
  border: 1px solid #ddd;
  border-radius: 8px;
  margin-bottom: 12px;
  font-family: 'Courier New', monospace;
}

.key-input:focus {
  outline: none;
  border-color: #4f46e5;
  box-shadow: 0 0 0 3px rgba(79, 70, 229, 0.1);
}

.error-msg {
  font-size: 14px;
  color: #dc2626;
  margin-bottom: 12px;
}

.btn-primary {
  width: 100%;
  padding: 14px;
  font-size: 16px;
  font-weight: 600;
  color: #fff;
  background: #4f46e5;
  border: none;
  border-radius: 8px;
  cursor: pointer;
}

.btn-primary:hover {
  background: #4338ca;
}

.btn-primary:disabled {
  background: #ccc;
  cursor: not-allowed;
}
```

## 交互逻辑

1. **打开注册页面按钮**
   - 用户点击"点这里，我帮你打开注册页面"
   - 调用 `window.open('https://platform.deepseek.com/api_keys', '_blank')`
   - 当前窗口不关闭，等待用户回来粘贴

2. **Key 输入框**
   - type="password" 显示为密码框（隐藏字符）
   - 用户粘贴 Key
   - 失焦时不验证格式（避免打扰）

3. **开始按钮**
   - 用户点击"开始"
   - 前端校验格式：`/^sk-[a-zA-Z0-9]{32,}$/`
   - 格式错误 → 显示错误提示："Key 格式不正确，应该是 sk- 开头的字符串"
   - 格式正确 → 禁用按钮（防重复点击）→ 发送到后端验证

4. **后端验证**
   - 调用 DeepSeek API 发起一次最小请求（chat.completions, max_tokens=1）
   - 验证成功 → 切换到聊天界面
   - 验证失败 → 显示错误提示："Key 无效或已过期，请检查后重新粘贴"，恢复按钮

## 状态管理

- 初始状态：输入框空，开始按钮可点击
- 验证中：开始按钮禁用，文本改为"验证中..."
- 验证失败：恢复按钮，显示错误消息
- 验证成功：页面切换到聊天界面（由后端控制）