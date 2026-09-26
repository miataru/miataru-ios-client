#!/usr/bin/env python3
import ast,json,os,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; HOOK=ROOT/"scripts/codex-hook.py"
def read_simple_toml(file):
 result={}; section=result
 for raw in file.read_text().splitlines():
  line=raw.strip()
  if not line or line.startswith('#'):continue
  if line.startswith('['):
   section=result.setdefault(line.strip('[]'),{});continue
  key,value=(part.strip() for part in line.split('=',1))
  section[key]={'true':True,'false':False}.get(value,ast.literal_eval(value) if value not in ('true','false') else None)
 return result
def run(root,kind,event):return subprocess.run([sys.executable,str(HOOK),kind],input=json.dumps(event),text=True,capture_output=True,env={**os.environ,"MIATARU_CODEX_TEAM_STATE_ROOT":str(root)})
required={"name","description","developer_instructions","model","model_reasoning_effort","sandbox_mode"}; expected={"coder":("gpt-6-luna","medium","workspace-write"),"senior_coder":("gpt-6-luna","high","workspace-write"),"researcher":("gpt-6-luna","low","read-only"),"simulator_debugger":("gpt-6-luna","medium","workspace-write"),"reviewer":("gpt-6-luna","high","read-only")}
config=read_simple_toml(ROOT/".codex/config.toml"); assert config["agents"]["enabled"] and config["agents"]["max_concurrent_threads_per_session"]==2
json.loads((ROOT/".codex/hooks.json").read_text())
seen={}
for f in (ROOT/".codex/agents").glob("*.toml"):
 d=read_simple_toml(f); assert set(d)==required; seen[d["name"]]=(d["model"],d["model_reasoning_effort"],d["sandbox_mode"])
assert seen==expected
with tempfile.TemporaryDirectory() as d:
 r=Path(d); a={"session_id":"a"}; b={"session_id":"b"}; good={"fork_turns":"none","model":"gpt-6-luna","model_reasoning_effort":"medium","role":"coder","task_name":"slice_luna"}
 assert run(r,"pretool",{**a,"tool_name":"Agent","input":good}).returncode!=0
 assert run(r,"prompt",{**a,"prompt":"mit Team"}).returncode==0 and run(r,"pretool",{**a,"tool_name":"Agent","input":good}).returncode==0
 assert run(r,"pretool",{**a,"tool_name":"Agent","input":{**good,"agent_type":"reviewer","role":"" ,"model":"gpt-6-luna","model_reasoning_effort":"high"}}).returncode==0
 assert run(r,"pretool",{**a,"tool_name":"Agent","input":{**good,"agent_type":"generic","model":"gpt-6-luna","model_reasoning_effort":"high"}}).returncode!=0
 for bad in ({**good,"fork_turns":"all"},{**good,"model":"gpt-5.6-terra"},{**good,"model":""},{**good,"model_reasoning_effort":"low"}):assert run(r,"pretool",{**a,"tool_name":"Agent","input":bad}).returncode!=0
 assert run(r,"pretool",{**a,"tool_name":"Agent","input":{**good,"task_name":"slice"}}).returncode!=0
 assert run(r,"prompt",{**a,"prompt":"Sol-Subagent einmalig freigeben: audit_sol"}).returncode==0
 sol={"fork_turns":"none","model":"gpt-5.6-sol","model_reasoning_effort":"high","task_name":"audit_sol","note":"approved"}
 assert run(r,"pretool",{**a,"tool_name":"Agent","input":sol}).returncode==0 and run(r,"pretool",{**a,"tool_name":"Agent","input":sol}).returncode!=0
 assert run(r,"prompt",{**a,"prompt":"Team deaktivieren"}).returncode==0 and run(r,"pretool",{**a,"tool_name":"Agent","input":good}).returncode!=0
 assert run(r,"pretool",{**b,"tool_name":"Agent","input":good}).returncode!=0
print("PASS codex hooks smoke")
