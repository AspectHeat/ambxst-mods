#!/usr/bin/env python3
"""Check that properties a package assigns to another component actually exist.

qmllint cannot resolve Quickshell's `qs.*` modules, so it never sees that a mod
assigns `toggleEnabled: ...` to a component whose 1.3.2 version has no such
property. That only surfaces when the QML engine instantiates the tree, which
inside the mod manager means failing the startup health window and rolling back.

This closes the gap statically: for every component a package's own QML files
instantiate, resolve the type to a .qml file in the composed tree and confirm
each assigned name is declared there. Only types that resolve to a file in the
tree are checked, so Qt's own components are left alone.

Usage: check-props.py <composed-tree> <package-dir> [<package-dir>...]
Exit:  0 clean, 1 findings, 2 could not run.
"""
import json, os, re, sys

# Names inherited from Qt/Quickshell bases or attached, not declared per file.
BUILTIN = {
    "id","objectName","anchors","width","height","x","y","z","opacity","visible",
    "enabled","clip","state","states","transitions","parent","data","children",
    "implicitWidth","implicitHeight","scale","rotation","transform","transformOrigin",
    "focus","activeFocus","antialiasing","smooth","layer","baselineOffset",
    "containmentMask","childrenRect","spacing","padding","topPadding","bottomPadding",
    "leftPadding","rightPadding","font","color","text","source","radius","border",
    "model","delegate","sourceComponent","active","asynchronous","item","status",
    "interval","repeat","running","triggeredOnStart","target","property","value",
    "duration","easing","from","to","loops","wrapMode","elide","horizontalAlignment",
    "verticalAlignment","textFormat","maximumLineCount","lineHeight","fillMode",
    "hoverEnabled","acceptedButtons","cursorShape","propagateComposedEvents",
    "checked","checkable","flat","down","pressed","hovered","indicator","background",
    "contentItem","currentIndex","count","orientation","policy","contentWidth",
    "contentHeight","boundsBehavior","flickableDirection","interactive","required",
}
ATTACHED = re.compile(r'^(Layout|Accessible|Keys|Drag|StackView|ScrollBar|ScrollView|Binding)\.')
DECL = re.compile(
    r'^\s*(?:readonly\s+|default\s+)?property\s+(?:alias\s+|[\w<>.]+\s+)([A-Za-z_]\w*)\s*[:;]'
    r'|^\s*signal\s+([A-Za-z_]\w*)'
    r'|^\s*(?:required\s+)?property\s+[\w<>.]+\s+([A-Za-z_]\w*)\s*$'
    r'|^\s*function\s+([A-Za-z_]\w*)\s*\('
)
# `Type {` opening a block, captured with its indentation
OPEN = re.compile(r'^(\s*)([A-Z]\w*)\s*\{\s*$')
ASSIGN = re.compile(r'^\s*(?:on([A-Z]\w*)|([a-z_]\w*(?:\.\w+)*))\s*:')

def declared(path, tree, seen=None):
    """Property/signal/function names a .qml file declares, following its root type."""
    if seen is None: seen = set()
    if path in seen: return set()
    seen.add(path)
    names, root = set(), None
    try: lines = open(path, encoding='utf-8', errors='replace').read().split('\n')
    except OSError: return names
    for ln in lines:
        m = DECL.match(ln)
        if m: names.add(next(g for g in m.groups() if g))
        if root is None:
            r = re.match(r'^([A-Z]\w*)\s*\{', ln)
            if r: root = r.group(1)
    if root:
        p = resolve(root, tree)
        if p and p != path: names |= declared(p, tree, seen)
    return names

_index = {}
def build_index(tree):
    for dirpath, _, files in os.walk(tree):
        if '/.git' in dirpath or '/backend' in dirpath: continue
        for f in files:
            if f.endswith('.qml'):
                _index.setdefault(f[:-4], os.path.join(dirpath, f))

def resolve(typename, tree):
    return _index.get(typename)

def strip_noise(line):
    """Drop // comments and string bodies so brace counting is not fooled."""
    out, i, n, q = [], 0, len(line), None
    while i < n:
        c = line[i]
        if q:
            if c == '\\': i += 2; continue
            if c == q: q = None
            i += 1; continue
        if c in '"\'':
            q = c; i += 1; continue
        if c == '/' and i+1 < n and line[i+1] == '/': break
        out.append(c); i += 1
    return ''.join(out)

def check(qml, tree):
    """Yield (line, type, prop) for assignments to names the type does not declare.

    Frames are tracked by real brace depth. A `Type {` opens a component frame; any
    other `{` or `[` opens an opaque one. An assignment is only attributed to a
    component when that component's frame is the innermost, which is what keeps the
    keys of an object literal inside `actions: [{ ... }]` from being read as
    properties of the surrounding component.
    """
    try:
        lines = open(qml, encoding='utf-8', errors='replace').read().split('\n')
    except OSError:
        return []
    out, stack = [], []   # stack of (kind, typename, declared) ; kind in {"c","o"}
    for i, raw in enumerate(lines, 1):
        ln = strip_noise(raw)
        stripped = ln.strip()

        # an assignment is judged before this line's own braces are counted
        a = ASSIGN.match(ln)
        if a and stack and stack[-1][0] == 'c':
            _, tn, names = stack[-1]
            if names is not None:
                sig, plain = a.group(1), a.group(2)
                if sig:
                    base = sig[0].lower() + sig[1:]
                    if not base.endswith('Changed') and base not in names \
                       and base not in BUILTIN and f"{base}Changed" not in names:
                        out.append((i, tn, f"on{sig}"))
                elif plain:
                    head = plain.split('.')[0]
                    if not (ATTACHED.match(plain) or head in BUILTIN or head in names):
                        out.append((i, tn, plain))

        # now advance the frame stack over this line's brackets
        m = re.match(r'^([A-Z]\w*)\s*\{', stripped)
        opened_component = False
        for ch in ln:
            if ch in '{[':
                if ch == '{' and m and not opened_component:
                    tn = m.group(1)
                    path = resolve(tn, tree)
                    names = declared(path, tree) if path and os.path.abspath(path) != os.path.abspath(qml) else None
                    stack.append(('c', tn, names))
                    opened_component = True
                else:
                    stack.append(('o', None, None))
            elif ch in '}]':
                if stack: stack.pop()
    return out

def main():
    if len(sys.argv) < 3: print(__doc__); return 2
    tree, pkgs = sys.argv[1], sys.argv[2:]
    build_index(tree)
    findings = 0
    for pkg in pkgs:
        mf = os.path.join(pkg, 'ambxst.mod.json')
        if not os.path.isfile(mf): continue
        d = json.load(open(mf))
        print(f"== {d['id']}")
        for op in d['operations']:
            if op.get('type') != 'overlay': continue
            src = os.path.join(pkg, op['source'])
            if not src.endswith('.qml'): continue
            # check the composed copy, so sibling types resolve
            for line, tn, prop in check(os.path.join(tree, op['target']), tree):
                print(f"  {op['target']}:{line}: {tn} has no property {prop!r}")
                findings += 1
    print(("no findings" if not findings else f"{findings} finding(s)"))
    return 1 if findings else 0

if __name__ == '__main__':
    sys.exit(main())
