#!/usr/bin/env python3
"""
Simple local web UI for browsing Xcode screenshot attachments.

Usage:
  python3 Scripts/view-test-artifacts.py \
    --artifact-dir .build/TestArtifacts/docker-ui/test-docker-ui-sim-20260322-231147 \
    --port 8765
"""

import argparse
import json
import mimetypes
import webbrowser
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict, List, Union
from urllib.parse import unquote, urlparse

IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".heic", ".gif"}


HTML = """<!doctype html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Xcode Screenshot Reviewer</title>
  <style>
    :root {
      font-family: "Inter", -apple-system, "SF Pro Text", Arial, sans-serif;
      --bg: #f6f8fa;
      --card: #ffffff;
      --line: #d8dde6;
      --text: #1f2937;
      --muted: #64748b;
      --accent: #2563eb;
      --good: #10b981;
    }

    * {
      box-sizing: border-box;
    }

    body {
      margin: 0;
      background: var(--bg);
      color: var(--text);
    }

    header {
      position: sticky;
      top: 0;
      z-index: 2;
      background: rgba(246, 248, 250, 0.94);
      backdrop-filter: blur(8px);
      border-bottom: 1px solid var(--line);
      padding: 1rem 1.25rem;
    }

    h1 {
      margin: 0;
      font-size: 1.25rem;
    }

    .meta {
      color: var(--muted);
      font-size: 0.9rem;
      margin-top: 0.25rem;
    }

    .toolbar {
      margin-top: 0.75rem;
      display: flex;
      gap: 0.5rem;
      flex-wrap: wrap;
      align-items: center;
    }

    button {
      border: 1px solid var(--line);
      background: #fff;
      padding: 0.45rem 0.85rem;
      border-radius: 999px;
      cursor: pointer;
    }

    button.primary {
      border-color: var(--accent);
      color: #fff;
      background: var(--accent);
    }

    button:disabled {
      opacity: 0.5;
      cursor: not-allowed;
    }

    #selected-count {
      font-weight: 600;
      margin-left: auto;
    }

    .container {
      padding: 1rem;
      max-width: 1200px;
      margin: 0 auto;
    }

    .test-card {
      background: var(--card);
      border: 1px solid var(--line);
      border-radius: 10px;
      margin-bottom: 1rem;
      overflow: hidden;
    }

    .test-head {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 0.75rem;
      padding: 0.75rem 1rem;
      border-bottom: 1px solid var(--line);
      cursor: pointer;
    }

    .test-head .title {
      font-weight: 600;
      word-break: break-word;
    }

    .test-meta {
      color: var(--muted);
      font-size: 0.9rem;
      margin-top: 0.2rem;
    }

    .thumbs {
      padding: 0.9rem;
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
      gap: 0.75rem;
    }

    .shot {
      border: 1px solid var(--line);
      background: #fff;
      border-radius: 8px;
      overflow: hidden;
    }

    .shot img {
      width: 100%;
      height: 280px;
      object-fit: contain;
      background: #111827;
      display: block;
      cursor: zoom-in;
    }

    .shot-content {
      padding: 0.65rem;
      display: grid;
      gap: 0.25rem;
      font-size: 0.84rem;
      color: #334155;
    }

    .shot-title {
      font-weight: 600;
      min-height: 1.5em;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    .shot-meta {
      color: var(--muted);
      font-size: 0.75rem;
      line-height: 1.25;
    }

    .shot {
      outline: 0 solid transparent;
      transition: outline-color 120ms ease;
    }

    .shot.wrong {
      outline-width: 3px;
      outline-style: solid;
      outline-color: var(--accent);
    }

    .shot.good {
      outline-width: 3px;
      outline-style: solid;
      outline-color: var(--good);
    }

    .shot-options {
      margin-top: 0.35rem;
      display: flex;
      flex-direction: column;
      gap: 0.35rem;
    }

    .shot-option {
      display: flex;
      align-items: center;
      gap: 0.35rem;
    }

    .shot-comment {
      margin-top: 0.35rem;
      width: 100%;
      min-height: 2.75rem;
      padding: 0.4rem 0.5rem;
      border: 1px solid var(--line);
      border-radius: 6px;
      resize: vertical;
      font: inherit;
      color: var(--text);
      font-size: 0.78rem;
      line-height: 1.35;
    }

    .empty {
      padding: 2rem;
      color: var(--muted);
      text-align: center;
      border: 1px dashed var(--line);
      border-radius: 8px;
      background: #fff;
    }
  </style>
</head>
<body>
  <header>
    <h1>Xcode Screenshot Reviewer</h1>
    <div class="meta" id="artifactPath"></div>
    <div class="toolbar">
      <button id="btnMarkAllWrong">Mark all wrong</button>
      <button id="btnClearAll">Clear all</button>
      <button id="btnExport" class="primary" disabled>Export selected as JSON</button>
      <span id="selected-count">0 selected</span>
    </div>
  </header>

  <main class="container">
    <div id="content" class="empty">Loading artifacts...</div>
  </main>

  <script>
    const decisions = {};
    const comments = {};
    const content = document.getElementById("content");
    const selectedCount = document.getElementById("selected-count");
    const btnExport = document.getElementById("btnExport");
    const btnMarkAllWrong = document.getElementById("btnMarkAllWrong");
    const btnClearAll = document.getElementById("btnClearAll");
    const pathLabel = document.getElementById("artifactPath");
    let data = null;

    const key = (testIdentifier, fileName, timestamp, index) =>
      `${testIdentifier}::${fileName}::${timestamp || ""}::${index}`;

    function getWrongCount() {
      return Object.values(decisions).filter((status) => status === "wrong").length;
    }

    function updateSelectedCount() {
      const wrongCount = getWrongCount();
      selectedCount.textContent = `${wrongCount} selected`;
      btnExport.disabled = wrongCount === 0;
    }

    function applyDecisionToShot(box) {
      const shotKey = box.dataset.shotKey;
      const decision = decisions[shotKey];

      const wrongInput = box.querySelector('input[value="wrong"]');
      const goodInput = box.querySelector('input[value="good"]');
      const commentInput = box.querySelector(".shot-comment");

      if (wrongInput) {
        wrongInput.checked = decision === "wrong";
      }
      if (goodInput) {
        goodInput.checked = decision === "good";
      }
      if (commentInput) {
        commentInput.value = comments[shotKey] || "";
      }

      box.classList.remove("wrong", "good");
      if (decision === "wrong") {
        box.classList.add("wrong");
      }
      if (decision === "good") {
        box.classList.add("good");
      }
    }

    function applySelectionToUI() {
      content.querySelectorAll(".shot").forEach((box) => {
        applyDecisionToShot(box);
      });
      updateSelectedCount();
    }

    function setTestDecision(test, status) {
      test.attachments.forEach((shot, index) => {
        const shotKey = key(test.testIdentifier, shot.exportedFileName, shot.timestamp, index);
        if (status === "wrong" || status === "good") {
          decisions[shotKey] = status;
        } else {
          delete decisions[shotKey];
          delete comments[shotKey];
        }
      });
    }

    function renderArtifactList(payload) {
      data = payload;
      pathLabel.textContent = payload.artifactDir;
      const tests = payload.tests || [];

      if (!tests.length) {
        content.className = "empty";
        content.textContent = "No screenshot attachments found in this run.";
        updateSelectedCount();
        return;
      }

      content.className = "";
      content.innerHTML = "";

      for (const test of tests) {
        const card = document.createElement("section");
        card.className = "test-card";

        const head = document.createElement("div");
        head.className = "test-head";

        const title = document.createElement("div");
        const titleLine = document.createElement("div");
        titleLine.className = "title";
        titleLine.textContent = test.testIdentifier;
        const meta = document.createElement("div");
        meta.className = "test-meta";
        meta.textContent = `${test.attachments.length} screenshot(s)`;
        title.appendChild(titleLine);
        title.appendChild(meta);

      const actions = document.createElement("div");
      actions.className = "toolbar";

      const btnSel = document.createElement("button");
      btnSel.textContent = "Mark this test wrong";
      btnSel.onclick = () => {
        setTestDecision(test, "wrong");
        applySelectionToUI();
        updateSelectedCount();
      };

      const btnGood = document.createElement("button");
      btnGood.textContent = "Mark this test good";
      btnGood.onclick = () => {
        setTestDecision(test, "good");
        applySelectionToUI();
        updateSelectedCount();
      };

      const btnClr = document.createElement("button");
      btnClr.textContent = "Clear this test";
      btnClr.onclick = () => {
        setTestDecision(test, "clear");
        applySelectionToUI();
        updateSelectedCount();
      };

      actions.appendChild(btnSel);
      actions.appendChild(btnGood);
      actions.appendChild(btnClr);
        head.appendChild(title);
        head.appendChild(actions);
        card.appendChild(head);

        const thumbs = document.createElement("div");
        thumbs.className = "thumbs";

        test.attachments.forEach((shot, index) => {
          const shotKey = key(test.testIdentifier, shot.exportedFileName, shot.timestamp, index);
          const box = document.createElement("div");
          box.className = "shot";
          box.dataset.shotKey = shotKey;

          const img = document.createElement("img");
          img.src = shot.url;
          img.alt = shot.suggestedHumanReadableName || shot.exportedFileName;

          const shotContent = document.createElement("div");
          shotContent.className = "shot-content";

          const shotTitle = document.createElement("div");
          shotTitle.className = "shot-title";
          shotTitle.textContent = shot.suggestedHumanReadableName || shot.exportedFileName;

          const shotMeta = document.createElement("div");
          shotMeta.className = "shot-meta";
          shotMeta.textContent = `${shot.exportedFileName}  ·  ${shot.deviceName || "unknown device"}`;

          const options = document.createElement("div");
          options.className = "shot-options";

          const wrongRow = document.createElement("label");
          wrongRow.className = "shot-option";
          const wrongInput = document.createElement("input");
          wrongInput.type = "radio";
          wrongInput.name = `decision-${shotKey}`;
          wrongInput.value = "wrong";
          wrongInput.onchange = () => {
            decisions[shotKey] = "wrong";
            applyDecisionToShot(box);
            updateSelectedCount();
          };
          const wrongText = document.createElement("span");
          wrongText.textContent = "Looks wrong";
          wrongRow.appendChild(wrongInput);
          wrongRow.appendChild(wrongText);

          const goodRow = document.createElement("label");
          goodRow.className = "shot-option";
          const goodInput = document.createElement("input");
          goodInput.type = "radio";
          goodInput.name = `decision-${shotKey}`;
          goodInput.value = "good";
          goodInput.onchange = () => {
            decisions[shotKey] = "good";
            applyDecisionToShot(box);
            updateSelectedCount();
          };
          const goodText = document.createElement("span");
          goodText.textContent = "Looks good";
          goodRow.appendChild(goodInput);
          goodRow.appendChild(goodText);

          const comment = document.createElement("textarea");
          comment.className = "shot-comment";
          comment.placeholder = "Comment";
          comment.rows = 2;
          comment.value = comments[shotKey] || "";
          comment.oninput = (evt) => {
            const value = evt.target.value;
            if (value) {
              comments[shotKey] = value;
            } else {
              delete comments[shotKey];
            }
          };

          options.appendChild(wrongRow);
          options.appendChild(goodRow);
          options.appendChild(comment);

          shotContent.appendChild(shotTitle);
          shotContent.appendChild(shotMeta);
          shotContent.appendChild(options);

          box.appendChild(img);
          box.appendChild(shotContent);
          thumbs.appendChild(box);
        });

        card.appendChild(thumbs);
        content.appendChild(card);
      }

      applySelectionToUI();
      updateSelectedCount();
    }

    btnMarkAllWrong.onclick = () => {
      if (!data) return;
      data.tests.forEach((test) => {
        setTestDecision(test, "wrong");
      });
      applySelectionToUI();
      updateSelectedCount();
    };

    btnClearAll.onclick = () => {
      Object.keys(decisions).forEach((shotKey) => {
        delete decisions[shotKey];
      });
      Object.keys(comments).forEach((shotKey) => {
        delete comments[shotKey];
      });
      applySelectionToUI();
      updateSelectedCount();
    };

    btnExport.onclick = () => {
      const exported = {
        exportedAt: new Date().toISOString(),
        artifactDir: data.artifactDir,
        selectedCount: getWrongCount(),
        screenshots: []
      };

      for (const test of data.tests) {
        test.attachments.forEach((shot, index) => {
          const shotKey = key(test.testIdentifier, shot.exportedFileName, shot.timestamp, index);
          if (decisions[shotKey] !== "wrong") {
            return;
          }
          exported.screenshots.push({
            testIdentifier: test.testIdentifier,
            testIdentifierURL: test.testIdentifierURL,
            exportedFileName: shot.exportedFileName,
            suggestedHumanReadableName: shot.suggestedHumanReadableName,
            fileUrl: shot.url,
            timestamp: shot.timestamp,
            isAssociatedWithFailure: shot.isAssociatedWithFailure,
            configurationName: shot.configurationName,
            deviceId: shot.deviceId,
            deviceName: shot.deviceName,
            decision: "wrong",
            comment: comments[shotKey] || ""
          });
        });
      }

      const blob = new Blob([JSON.stringify(exported, null, 2)], {
        type: "application/json"
      });
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement("a");
      anchor.href = url;
      anchor.download = "wrong_screenshots.json";
      anchor.click();
      URL.revokeObjectURL(url);
    };

    fetch("/api/manifest")
      .then((r) => r.json())
      .then((payload) => renderArtifactList(payload))
      .catch((err) => {
        content.className = "empty";
        content.textContent = `Failed to load manifest: ${err}`;
      });
  </script>
</body>
</html>
"""


def parse_manifest(artifact_dir: Path) -> List[Dict[str, Any]]:
    manifest_path = artifact_dir / "manifest.json"
    if not manifest_path.exists():
        raise FileNotFoundError(f"manifest.json not found at {manifest_path}")

    with open(manifest_path, "r", encoding="utf-8") as f:
        raw_manifest = json.load(f)

    tests = []
    for test in raw_manifest:
        attachments = []
        for attachment in test.get("attachments", []):
            file_name = Path(attachment.get("exportedFileName", "")).name
            if not file_name:
                continue
            suffix = Path(file_name).suffix.lower()
            if suffix not in IMAGE_EXTENSIONS:
                continue
            shot = dict(attachment)
            shot["exportedFileName"] = file_name
            shot["url"] = f"/assets/{file_name}"
            attachments.append(shot)

        if not attachments:
            continue
        tests.append(
            {
                "testIdentifier": test.get("testIdentifier"),
                "testIdentifierURL": test.get("testIdentifierURL"),
                "attachments": attachments,
            }
        )

    return tests


def resolve_artifact_dir(path: Path) -> Path:
    if (path / "manifest.json").exists():
        return path

    candidates = [
        entry
        for entry in sorted(path.iterdir())
        if entry.is_dir() and (entry / "manifest.json").exists()
    ]
    if candidates:
        latest = max(candidates, key=lambda entry: entry.stat().st_mtime)
        return latest

    raise FileNotFoundError(f"No manifest.json found under {path}")


class ArtifactViewerHandler(BaseHTTPRequestHandler):
    artifact_dir: Path
    tests_payload: List[Dict[str, Any]]

    def _write_json(self, status: int, payload: Union[Dict[str, Any], List[Any]]):
        body = json.dumps(payload, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _write_html(self):
        body = HTML.encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        path = unquote(parsed.path or "/")

        if path == "/" or path == "/index.html":
            self._write_html()
            return

        if path == "/api/manifest":
            payload = {
                "artifactDir": str(self.artifact_dir),
                "tests": self.tests_payload,
            }
            self._write_json(HTTPStatus.OK, payload)
            return

        if path.startswith("/assets/"):
            requested = path.removeprefix("/assets/")
            filename = Path(requested)
            if filename.name != filename.as_posix():
                self.send_error(HTTPStatus.BAD_REQUEST, "invalid asset path")
                return

            asset_path = self.artifact_dir / filename.name
            if not asset_path.exists() or asset_path.suffix.lower() not in IMAGE_EXTENSIONS:
                self.send_error(HTTPStatus.NOT_FOUND, "asset not found")
                return

            with open(asset_path, "rb") as f:
                body = f.read()
            ctype, _ = mimetypes.guess_type(str(asset_path))
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", ctype or "application/octet-stream")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        self.send_error(HTTPStatus.NOT_FOUND, "not found")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--artifact-dir",
        default=".build/TestArtifacts/docker-ui",
        help=(
            "Path to an exported artifact directory, or a folder containing "
            "multiple artifact runs. If manifest.json is missing, the latest "
            "run folder is selected automatically."
        ),
    )
    parser.add_argument("--port", type=int, default=8765, help="Port for web UI.")
    parser.add_argument(
        "--open",
        action="store_true",
        help="Open browser automatically.",
    )
    args = parser.parse_args()

    artifact_dir = resolve_artifact_dir(Path(args.artifact_dir).expanduser().resolve())
    tests_payload = parse_manifest(artifact_dir)

    handler = ArtifactViewerHandler
    handler.artifact_dir = artifact_dir
    handler.tests_payload = tests_payload

    addr = ("", args.port)
    with ThreadingHTTPServer(addr, handler) as httpd:
        url = f"http://127.0.0.1:{args.port}"
        print(f"Serving {artifact_dir} at {url}")
        print("Open in browser: " + url)
        if args.open:
            webbrowser.open(url)
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
