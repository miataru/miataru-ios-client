#!/usr/bin/env python3
"""Defence-in-depth hook; config and Root policy remain authoritative."""
import hashlib,json,os,re,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
STATE_ROOT=Path(os.environ.get("MIATARU_CODEX_TEAM_STATE_ROOT",ROOT/"miataru/artifacts/codex-team-state"))
ROLES={"coder":("gpt-6-luna","medium"),"senior_coder":("gpt-6-luna","high"),"researcher":("gpt-6-luna","low"),"simulator_debugger":("gpt-6-luna","medium"),"reviewer":("gpt-6-luna","high")}
def path(s): return STATE_ROOT/(hashlib.sha256(s.encode()).hexdigest()[:32]+".json")
def read(s):
 try:return json.loads(path(s).read_text())
 except (OSError,ValueError):return {"active":False,"grants":[]}
def write(s,v):
 STATE_ROOT.mkdir(parents=True,exist_ok=True); t=path(s).with_suffix(".tmp"); t.write_text(json.dumps(v,sort_keys=True)+"\n"); os.replace(t,path(s))
def main(kind):
 e=json.load(sys.stdin) if not sys.stdin.isatty() else {}; s=str(e.get("session_id",""))
 if not s: print("Hook denied: session_id is required.",file=sys.stderr); return 2
 st=read(s)
 if kind=="end": return 0
 if kind=="prompt":
  text=str(e.get("prompt",e.get("user_prompt",e.get("text","")))).strip()
  if re.fullmatch(r"(?:mit Team|Team aktivieren)",text,re.I):st.update(active=True,grants=[])
  elif re.fullmatch(r"(?:ohne Team|Team deaktivieren)",text,re.I):st.update(active=False,grants=[])
  else:
   g=re.fullmatch(r"Sol-Subagent einmalig freigeben: (.+)",text)
   if g and st.get("active"):st.setdefault("grants",[]).append(g.group(1).strip())
  write(s,st); return 0
 tool=e.get("tool_name",e.get("toolName",e.get("name",""))); p=e.get("input",e.get("arguments",e))
 if tool not in ("spawn_agent","Agent"):return 0
 if not st.get("active"):print("Team delegation denied: explicitly enable with 'mit Team'.",file=sys.stderr);return 2
 if not isinstance(p,dict) or p.get("fork_turns")!="none" or not isinstance(p.get("model"),str) or not isinstance(p.get("model_reasoning_effort",p.get("reasoning_effort")),str):print("Team delegation denied: explicit model, effort, and fork_turns='none' required.",file=sys.stderr);return 2
 role=p.get("agent_type",p.get("role")); model=p["model"]; effort=p.get("model_reasoning_effort",p.get("reasoning_effort")); task=str(p.get("task_name","")).strip()
 suffix="_sol" if model=="gpt-5.6-sol" else "_luna"
 if not task.endswith(suffix):print(f"Team delegation denied: task name must end in {suffix}.",file=sys.stderr);return 2
 if role in ROLES and (model,effort)!=ROLES[role]:print("Team delegation denied: role model/effort mismatch.",file=sys.stderr);return 2
 if role not in ROLES and model!="gpt-5.6-sol" and (model,effort)!=("gpt-6-luna","medium"):print("Team delegation denied: generic agents must use Luna 6/medium.",file=sys.stderr);return 2
 if model=="gpt-5.6-sol":
  if not task or task not in st.get("grants",[]):print("Team delegation denied: no exact one-time Sol grant.",file=sys.stderr);return 2
  st["grants"].remove(task);write(s,st)
 return 0
if __name__=="__main__":raise SystemExit(main(sys.argv[1] if len(sys.argv)>1 else ""))
