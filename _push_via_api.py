import os, sys, json, base64, urllib.request, urllib.error

TOKEN = os.environ.get("NOOTI_TK", "") or (sys.argv[1] if len(sys.argv) > 1 else "")
if not TOKEN:
    print("no token")
    sys.exit(1)
REPO = "Posy0328/nooti_monitor"
ROOT = r"C:\Users\彭艺卉\Documents\作业库\Nooti\nooti_monitor"

FILES = [
    ".github/workflows/build.yml",
    "lib/main.dart",
    "overlay/android/app/src/main/AndroidManifest.xml",
    "overlay/android/app/src/main/kotlin/com/nooti/monitor/AlertActivity.kt",
    "overlay/android/app/src/main/kotlin/com/nooti/monitor/CardBuilder.kt",
    "overlay/android/app/src/main/kotlin/com/nooti/monitor/InboxStore.kt",
    "overlay/android/app/src/main/kotlin/com/nooti/monitor/MainActivity.kt",
    "overlay/android/app/src/main/kotlin/com/nooti/monitor/NootiListenerService.kt",
    "overlay/android/app/src/main/kotlin/com/nooti/monitor/OverlayAlert.kt",
]

MSG = "v7: overlay-window alert card (centered, dark scrim, no tap needed) instead of system heads-up; full inbox capture of every notification; overlay permission guide; 3-tab UI"


def api(method, path, body=None, raw=False):
    url = "https://api.github.com" + path
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": "token " + TOKEN,
        "Accept": "application/vnd.github+json",
        "User-Agent": "nooti-build",
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            txt = r.read().decode("utf-8")
            return json.loads(txt) if not raw else txt
    except urllib.error.HTTPError as e:
        print("HTTP", e.code, method, path)
        print(e.read().decode("utf-8", "ignore")[:600])
        raise


base = api("GET", f"/repos/{REPO}/git/refs/heads/main")["object"]["sha"]
print("base commit:", base)

base_tree = api("GET", f"/repos/{REPO}/git/commits/{base}")["tree"]["sha"]
print("base tree  :", base_tree)

tree_items = []
for rel in FILES:
    p = os.path.join(ROOT, rel.replace("/", os.sep))
    with open(p, "rb") as f:
        content = f.read()
    b = api("POST", f"/repos/{REPO}/git/blobs", {
        "content": base64.b64encode(content).decode("ascii"),
        "encoding": "base64",
    })
    print("blob", rel, len(content), "->", b["sha"][:10])
    tree_items.append({"path": rel, "mode": "100644", "type": "blob", "sha": b["sha"]})

tree = api("POST", f"/repos/{REPO}/git/trees", {
    "base_tree": base_tree,
    "tree": tree_items,
})
print("new tree:", tree["sha"])

commit = api("POST", f"/repos/{REPO}/git/commits", {
    "message": MSG,
    "tree": tree["sha"],
    "parents": [base],
})
print("new commit:", commit["sha"])

api("PATCH", f"/repos/{REPO}/git/refs/heads/main", {"sha": commit["sha"], "force": False})
print("REF UPDATED ->", commit["sha"])
