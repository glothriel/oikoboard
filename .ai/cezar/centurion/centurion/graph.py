"""A small builder for cezar `version: 2` graph workflows, their structural checks (the ones cezar
applies, plus reachability) and a YAML emitter for exactly what the builder produces."""

import json
import re

PORTS = {"start": ["next"], "end": [], "loop": ["repeat", "exhausted"], "check": ["pass", "fail"],
         "if": ["true", "false"]}
NODE_REF = re.compile(r"\{\{\s*nodes\.([A-Za-z0-9_-]+)\.([A-Za-z0-9_]+)\s*\}\}")
NODE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]*$")


class Graph:
    def __init__(self, name, description):
        self.name = name
        self.description = description
        self.nodes = []   # dicts, in file order; {"comment": "..."} entries are YAML comments
        self.edges = []   # (from, to)
        self.commands = {}  # check node id -> (step name, args)

    # ---- nodes
    def _add(self, node):
        self.nodes.append(node)
        return node["id"]

    def comment(self, text):
        self.nodes.append({"comment": text})

    def start(self, id="start"):
        return self._add({"id": id, "type": "start"})

    def end(self, id, status="success", name=None):
        node = {"id": id, "type": "end"}
        if name:
            node["name"] = name
        node["status"] = status
        return self._add(node)

    def loop(self, id, name, max):
        return self._add({"id": id, "type": "loop", "name": name, "max": max})

    def check(self, id, name, command, step=None, args=()):
        self.commands[id] = (step, tuple(args))
        return self._add({"id": id, "type": "check", "name": name, "command": command})

    def if_contains(self, id, name, node, value):
        return self._add({"id": id, "type": "if", "name": name,
                          "condition": {"kind": "output", "ref": f"{node}.output", "op": "contains", "value": value}})

    def agent(self, id, name, prompt, verdicts=None, cont=None):
        node = {"id": id, "type": "agent", "name": name}
        if verdicts:
            node["verdicts"] = list(verdicts)
        if cont:
            node["session"] = {"continue": cont}
        node["prompt"] = prompt.strip("\n") + "\n"
        return self._add(node)

    def edge(self, frm, to):
        self.edges.append((frm, to))

    def edges_from(self, *pairs):
        for frm, to in pairs:
            self.edge(frm, to)

    # ---- structure
    def real_nodes(self):
        return [n for n in self.nodes if "id" in n]

    def ports(self, node):
        if node["type"] == "agent":
            return list(node.get("verdicts") or ["done"]) + ["failed"]
        return PORTS[node["type"]]

    def issues(self):
        """Structural problems (empty when sound): what cezar's graph validation checks, plus
        that every node is reachable from start."""
        nodes = self.real_nodes()
        by_id = {n["id"]: n for n in nodes}
        problems = []
        ids = [n["id"] for n in nodes]
        for i in ids:
            if ids.count(i) > 1:
                problems.append(f"duplicate node id {i}")
            if not NODE_ID.match(i):
                problems.append(f"bad node id {i}")
        starts = [n for n in nodes if n["type"] == "start"]
        if len(starts) != 1:
            problems.append(f"{len(starts)} start nodes")
        for n in nodes:
            if n["type"] == "agent":
                c = n.get("session", {}).get("continue")
                if c is not None:
                    if c == n["id"]:
                        problems.append(f"{n['id']}: session.continue names itself")
                    elif by_id.get(c, {}).get("type") != "agent":
                        problems.append(f"{n['id']}: session.continue names no agent ({c})")
                if len(set(n.get("verdicts", []))) != len(n.get("verdicts", [])):
                    problems.append(f"{n['id']}: repeated verdict")
                for v in n.get("verdicts", []):
                    if v in ("done", "failed"):
                        problems.append(f"{n['id']}: verdict {v} is reserved")
            if n["type"] == "if":
                ref = n["condition"]["ref"].split(".")[0]
                if ref not in by_id:
                    problems.append(f"{n['id']}: condition reads unknown node {ref}")
            for field in ("prompt", "command"):
                for m in NODE_REF.finditer(n.get(field, "")):
                    if m.group(1) not in by_id:
                        problems.append(f"{n['id']}: references unknown node {m.group(1)}")

        nxt, wired = {}, set()
        for frm, to in self.edges:
            node_id, _, port = frm.partition(".")
            node = by_id.get(node_id)
            if node is None:
                problems.append(f"edge from unknown node {frm}")
                continue
            port = port or (self.ports(node) or [""])[0]
            if port not in self.ports(node):
                problems.append(f"edge from {frm}: {node_id} has no port {port}")
            if (node_id, port) in wired:
                problems.append(f"port {node_id}.{port} wired twice")
            wired.add((node_id, port))
            if to not in by_id:
                problems.append(f"edge from {frm} to unknown node {to}")
            elif by_id[to]["type"] == "start":
                problems.append(f"edge from {frm} back into start")
            nxt.setdefault(node_id, []).append((port, to))

        # every node reachable from start
        if starts:
            seen, todo = set(), [starts[0]["id"]]
            while todo:
                cur = todo.pop()
                if cur in seen:
                    continue
                seen.add(cur)
                todo += [to for _, to in nxt.get(cur, [])]
            for i in ids:
                if i not in seen:
                    problems.append(f"{i} is not reachable from start")

        # every cycle passes a loop node's repeat port: no cycle without those edges
        bounded = {k: [to for port, to in v if not (by_id[k]["type"] == "loop" and port == "repeat")]
                   for k, v in nxt.items()}
        state = {}

        def visit(i, path):
            if state.get(i) == "open":
                return path[path.index(i):] + [i]
            if state.get(i) == "done":
                return None
            state[i] = "open"
            for to in bounded.get(i, []):
                hit = visit(to, path + [i])
                if hit:
                    return hit
            state[i] = "done"
            return None

        for i in ids:
            cycle = visit(i, [])
            if cycle:
                problems.append("cycle without a loop node: " + " -> ".join(cycle))
                break
        return problems

    def to_dict(self):
        return {"version": 2, "name": self.name, "description": self.description,
                "nodes": [{k: v for k, v in n.items()} for n in self.real_nodes()],
                "edges": [{"from": f, "to": t} for f, t in self.edges]}

    # ---- YAML
    def to_yaml(self, header=""):
        out = [header.rstrip("\n")] if header else []
        out += ["version: 2", f"name: {scalar(self.name)}", f"description: {scalar(self.description)}", "nodes:"]
        for n in self.nodes:
            if "comment" in n:
                out.append(f"  # {n['comment']}")
            elif "prompt" in n:
                out.append(f"  - id: {scalar(n['id'])}")
                for k, v in n.items():
                    if k in ("id", "prompt"):
                        continue
                    out.append(f"    {k}: {flow(v)}")
                out.append("    prompt: |")
                for line in n["prompt"].rstrip("\n").split("\n"):
                    out.append(("      " + line) if line else "")
            else:
                out.append(f"  - {flow(n)}")
        out.append("edges:")
        for f, t in self.edges:
            out.append(f"  - {{ from: {scalar(f)}, to: {scalar(t)} }}")
        return "\n".join(out) + "\n"


_PLAIN = re.compile(r"^[A-Za-z0-9_./(][A-Za-z0-9 _./()'+-]*$")
_RESERVED = {"true", "false", "null", "yes", "no", "on", "off", "y", "n", "~"}


def scalar(v):
    """A YAML scalar: plain when that is unambiguous (also inside flow collections), else a
    double-quoted string (JSON strings are valid YAML)."""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    s = str(v)
    if (_PLAIN.match(s) and not s.endswith(" ") and s.lower() not in _RESERVED
            and not re.fullmatch(r"[-+.0-9eE_]+", s)):
        return s
    return json.dumps(s, ensure_ascii=False)


def flow(v):
    if isinstance(v, dict):
        return "{ " + ", ".join(f"{k}: {flow(x)}" for k, x in v.items()) + " }"
    if isinstance(v, (list, tuple)):
        return "[" + ", ".join(flow(x) for x in v) + "]"
    return scalar(v)
