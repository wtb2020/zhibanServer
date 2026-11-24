const $ = s => document.querySelector(s);
const escapeHTML = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let currentUser = null;
async function api(path, method='GET', data){
  const response = await fetch(path, {method, headers: {'X-Portal':location.pathname==='/admin'?'admin':'client',...(data === undefined ? {} : {'Content-Type':'application/json'})}, body:data === undefined?undefined:JSON.stringify(data)});
  const result = await response.json();
  if(!response.ok){if(response.status===401 && location.pathname==='/admin' && !['/api/login','/api/register','/api/me'].includes(path)) location.reload(); const error=Error(result.error||'请求失败');error.status=response.status;throw error;}
  return result;
}
function shell(admin){
  $('#app').innerHTML=`<aside><a class="brand" href="/">✦ <span>知伴<span class="brand-sub">LEARNING COMPANION</span></span></a><div class="workspace">${admin?'服务端管理中心':'机器人客户端'}</div><nav>${admin?'<a href="#courses" id="nav-courses" class="active">▤　课程管理</a><a href="#users" id="nav-users">♙　用户与访问权限</a>':'<a href="#" id="nav-learning" class="active">▦　我的课堂</a>'}</nav><div class="aside-bottom"><b>${admin?'连接实物与知识':'让每一次触碰<br>都成为学习的开始。'}</b><p>${admin?'用户管理 · 课程管理 · 访问控制':'实物感知 · 知识连接 · 互动学习'}</p><a href="/">← 返回入口选择</a></div></aside><main><header><span>${admin?'服务端管理':'机器人客户端'}</span><div class="account"><span id="account-name"></span><button class="secondary" id="logout" hidden>退出登录</button></div></header><section class="page"><div id="workspace"></div><footer><span>✦ 知伴智慧教育实验室</span><span>${admin?'ADMIN CONSOLE':'ROBOT CLIENT'}</span></footer></section></main>`;
  $('#logout').onclick=async()=>{try{await api('/api/logout','POST',{});location.reload();}catch(e){alert(e.message);}};
}
async function authenticate(admin, onReady){
  shell(admin);
  try{const user=await api('/api/me');if(!admin||user.role==='admin')return ready(user);}catch{}
  authForm(false);
  function ready(user){currentUser=user;$('#account-name').textContent=user.username+' · '+(user.role==='admin'?'管理员':'学生');$('#logout').hidden=false;onReady();}
  function authForm(register){
    $('#workspace').innerHTML=`<div class="auth-card panel"><div class="eyebrow">${admin?'ADMIN CONSOLE':'ROBOT CLIENT'}</div><h1>${register?'注册学生账号':admin?'管理员登录':'欢迎来到知伴课堂'}</h1><p>${register?'注册后请联系管理员分配课程。':admin?'登录后管理课程、用户与访问权限。':'登录后下载课程，开始互动学习。'}</p><form id="auth-form"><label for="username">用户名</label><input id="username" autocomplete="username" required minlength="3" maxlength="40"><label for="password">密码</label><input id="password" type="password" autocomplete="${register?'new-password':'current-password'}" required minlength="8" maxlength="128">${register?'<label for="confirm-password">确认密码</label><input id="confirm-password" type="password" autocomplete="new-password" required>':''}<p id="auth-message" role="status"></p><button class="primary" id="auth-submit">${register?'创建学生账号':'登录'}</button></form>${!admin?`<button class="text-button" id="toggle-auth">${register?'已有账号？返回登录':'还没有账号？注册学生账号'}</button>`:'<p class="hint">首次管理员账号与随机密码显示在服务器启动窗口中。</p>'}<a class="text-button" href="/">返回入口选择</a></div>`;
    if(!admin)$('#toggle-auth').onclick=()=>authForm(!register);
    $('#auth-form').onsubmit=async e=>{e.preventDefault();const button=$('#auth-submit');button.disabled=true;try{const username=$('#username').value.trim(),password=$('#password').value;if(register){if(password!==$('#confirm-password').value)throw Error('两次输入的密码不一致');await api('/api/register','POST',{username,password});authForm(false);$('#username').value=username;$('#auth-message').textContent='注册成功，请登录。课程需管理员授权。';}else{const user=await api('/api/login','POST',{username,password,portal:admin?'admin':'client'});ready(user);}}catch(error){$('#auth-message').textContent=error.message;}finally{button.disabled=false;}};
  }
}
