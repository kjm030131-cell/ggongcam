// 폰에서 모은 사진과 YOLO 라벨을 GitHub 저장소 data/extra/phone/ 에 한 커밋으로 넣는다.
// Cloudflare Pages 환경 변수(Secret): GH_TOKEN (ggongcam 저장소 Contents 읽기/쓰기 권한 토큰), UPLOAD_CODE (업로드 비밀번호)
const REPO = 'kjm030131-cell/ggongcam', BRANCH = 'main', MAX_FILES = 40;

const json = (obj, status = 200) => new Response(JSON.stringify(obj), {status, headers: {'content-type': 'application/json; charset=utf-8'}});

async function gh(env, path, init = {}) {
  const r = await fetch('https://api.github.com/repos/' + REPO + path, {
    ...init,
    headers: {authorization: 'Bearer ' + env.GH_TOKEN, accept: 'application/vnd.github+json', 'user-agent': 'ggongcam-upload', 'x-github-api-version': '2022-11-28', ...(init.body ? {'content-type': 'application/json'} : {})},
  });
  if (!r.ok) throw new Error('GitHub ' + r.status + ' ' + (await r.text()).slice(0, 200));
  return r.json();
}

export async function onRequestPost({request, env}) {
  if (!env.GH_TOKEN || !env.UPLOAD_CODE) return json({error: '서버 설정이 아직 안 됐습니다 (GH_TOKEN, UPLOAD_CODE).'}, 503);
  let body;
  try { body = await request.json(); } catch { return json({error: '요청 형식이 잘못됐습니다.'}, 400); }
  if (!body || body.code !== env.UPLOAD_CODE) return json({error: '업로드 비밀번호가 맞지 않습니다.'}, 401);
  const items = Array.isArray(body.items) ? body.items.slice(0, MAX_FILES) : [];
  if (!items.length) return json({error: '보낼 사진이 없습니다.'}, 400);

  const day = new Date(Date.now() + 9 * 3600e3).toISOString().slice(0, 10);
  const files = []; let nTest = 0;
  for (const it of items) {
    const name = String(it.name || '').replace(/[^A-Za-z0-9_\-]/g, '').slice(0, 60);
    if (!name || typeof it.jpg !== 'string' || it.jpg.length > 8e6) continue;
    const labels = (Array.isArray(it.labels) ? it.labels : []).filter(l => Array.isArray(l) && l.length === 4 && l.every(v => typeof v === 'number' && v >= 0 && v <= 1));
    // 시험용 사진은 data/test 에 넣는다. 학습(data/extra)에는 절대 섞이지 않고 성적을 매기는 데만 쓴다.
    const root = it.split === 'test' ? 'data/test/phone' : 'data/extra/phone';
    const tags = (Array.isArray(it.tags) ? it.tags : []).map(t => String(t).replace(/[^a-z]/g, '').slice(0, 10)).filter(Boolean).slice(0, 6);
    const file = name + (tags.length ? '__' + tags.join('-') : '');
    if (it.split === 'test') nTest++;
    files.push({path: `${root}/${day}/images/${file}.jpg`, content: it.jpg, encoding: 'base64'});
    files.push({path: `${root}/${day}/labels/${file}.txt`, content: labels.map(l => '0 ' + l.map(v => v.toFixed(6)).join(' ')).join('\n') + (labels.length ? '\n' : ''), encoding: 'utf-8'});
  }
  if (!files.length) return json({error: '올바른 사진이 없습니다.'}, 400);

  try {
    const ref = await gh(env, `/git/ref/heads/${BRANCH}`);
    const head = await gh(env, `/git/commits/${ref.object.sha}`);
    const tree = [];
    for (const f of files) {
      const blob = await gh(env, '/git/blobs', {method: 'POST', body: JSON.stringify({content: f.content, encoding: f.encoding})});
      tree.push({path: f.path, mode: '100644', type: 'blob', sha: blob.sha});
    }
    const t = await gh(env, '/git/trees', {method: 'POST', body: JSON.stringify({base_tree: head.tree.sha, tree})});
    const n = files.length / 2, who = String(body.device || '폰').slice(0, 30);
    const c = await gh(env, '/git/commits', {method: 'POST', body: JSON.stringify({message: `폰에서 모은 사진 ${n}장 추가${nTest ? ` (그중 시험용 ${nTest}장)` : ''} (${who})`, tree: t.sha, parents: [ref.object.sha]})});
    await gh(env, `/git/refs/heads/${BRANCH}`, {method: 'PATCH', body: JSON.stringify({sha: c.sha})});
    return json({ok: true, added: n, commit: c.sha.slice(0, 7)});
  } catch (e) {
    return json({error: '저장소에 넣지 못했습니다. ' + String(e.message || e).slice(0, 160)}, 502);
  }
}

export async function onRequestGet({env}) {
  return json({ready: !!(env.GH_TOKEN && env.UPLOAD_CODE)});
}
