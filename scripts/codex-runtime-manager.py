#!/usr/bin/env python3
"""Codex runtime selector、驗證 cache 與離線 loader dispatch。

刻意把網路、檔案系統與程序邊界收在小型 adapter 後，讓正式與測試 caller
共用同一份 manager 契約。
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import io
import json
import os
import posixpath
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path, PurePosixPath
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence, Tuple


MODES = ("decomposition-gate", "sensitive-data-guard", "harness", "integrated-harness")
SCOPES = ("project", "local", "user")
SCHEMA_VERSION = 1
MAX_MANIFEST_BYTES = 1024 * 1024
MAX_ARCHIVE_BYTES = 64 * 1024 * 1024
MAX_ARCHIVE_FILES = 512
MAX_EXTRACTED_BYTES = 128 * 1024 * 1024
MAX_EVENT_BYTES = 2 * 1024 * 1024
MAX_OUTPUT_BYTES = 4 * 1024 * 1024
APPROVED_HOSTS = {"raw.githubusercontent.com", "github.com", "objects.githubusercontent.com"}
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
MODE_RE = re.compile(r"^[a-z0-9-]+$")
REF_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
SLOTS = {
    "pretool.decomposition",
    "pretool.plan",
    "pretool.security",
    "pretool.pii",
    "prompt.pii",
    "session.start",
}
MODE_SLOTS = {
    "decomposition-gate": {"pretool.decomposition"},
    "sensitive-data-guard": {"pretool.security", "pretool.pii", "prompt.pii"},
    "harness": {"pretool.plan", "pretool.security", "pretool.pii", "prompt.pii"},
    "integrated-harness": {"pretool.plan", "pretool.security", "pretool.pii", "prompt.pii", "session.start"},
}


class ManagerError(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code


def _error(code: str, message: str) -> ManagerError:
    return ManagerError(code, message)


def _json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")


def _safe_path(path: Path, *, parent: bool = False) -> Path:
    """在開啟路徑前拒絕受管邊界上的 symlink。"""
    target = path.parent if parent else path
    current = target
    missing: List[Path] = []
    while not current.exists() and current != current.parent:
        missing.append(current)
        current = current.parent
    if current.is_symlink():
        raise _error("E_SCOPE_UNSAFE", "managed path contains a symlink")
    for item in missing:
        if item.is_symlink():
            raise _error("E_SCOPE_UNSAFE", "managed path contains a symlink")
    return path


def _ensure_contained(root: Path, target: Path) -> None:
    try:
        target.resolve().relative_to(root.resolve())
    except ValueError:
        raise _error("E_ARCHIVE_UNSAFE", "path escaped managed root")


def _approved_url(value: Any) -> urllib.parse.ParseResult:
    if not isinstance(value, str):
        raise _error("E_SOURCE_DENIED", "source URL must be a string")
    try:
        parsed = urllib.parse.urlparse(value)
        port = parsed.port
    except ValueError:
        raise _error("E_SOURCE_DENIED", "source URL is invalid")
    if (parsed.scheme != "https" or parsed.hostname not in APPROVED_HOSTS
            or parsed.username or parsed.password or port not in (None, 443)
            or parsed.query or parsed.fragment):
        raise _error("E_SOURCE_DENIED", "source origin is not approved")
    return parsed


def _validate_ref(value: Any) -> str:
    if not isinstance(value, str) or not REF_RE.fullmatch(value):
        raise _error("E_MANIFEST_INVALID", "ref must be a simple tag, branch or commit name")
    return value


def _atomic_write(path: Path, data: bytes, mode: Optional[int] = None) -> None:
    _safe_path(path, parent=True)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.parent.is_symlink() or not path.parent.is_dir():
        raise _error("E_SCOPE_UNSAFE", "managed parent is not a real directory")
    fd, name = tempfile.mkstemp(prefix="." + path.name + ".", dir=str(path.parent))
    temporary = Path(name)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            try:
                os.fsync(stream.fileno())
            except OSError:
                pass
        if mode is not None:
            os.chmod(temporary, mode)
        os.replace(str(temporary), str(path))
    except BaseException:
        try:
            temporary.unlink()
        except OSError:
            pass
        raise


def _read_json(path: Path) -> Dict[str, Any]:
    _safe_path(path)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise _error("E_RUNTIME_MISSING", "selector or cache metadata is missing")
    except (OSError, UnicodeError, json.JSONDecodeError):
        raise _error("E_CACHE_CORRUPT", "managed JSON is invalid")
    if not isinstance(data, dict):
        raise _error("E_CACHE_CORRUPT", "managed JSON must be an object")
    return data


def _validate_relative(value: Any) -> str:
    if not isinstance(value, str) or not value or "\x00" in value or "\\" in value:
        raise _error("E_ARCHIVE_UNSAFE", "entrypoint must be a relative POSIX path")
    if value.startswith("/") or re.match(r"^[A-Za-z]:", value) or value.startswith("//"):
        raise _error("E_ARCHIVE_UNSAFE", "absolute entrypoint is not allowed")
    parts = value.split("/")
    if any(not part or part in (".", "..") for part in parts):
        raise _error("E_ARCHIVE_UNSAFE", "entrypoint contains an unsafe path segment")
    normalized = posixpath.normpath(value)
    if normalized != value:
        raise _error("E_ARCHIVE_UNSAFE", "entrypoint is not normalized")
    return value


def validate_manifest(raw: bytes, *, expected_ref: Optional[str] = None) -> Dict[str, Any]:
    if len(raw) > MAX_MANIFEST_BYTES:
        raise _error("E_MANIFEST_INVALID", "manifest exceeds size limit")
    try:
        data = json.loads(raw.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError):
        raise _error("E_MANIFEST_INVALID", "manifest is not valid UTF-8 JSON")
    if not isinstance(data, dict) or data.get("schema_version") != SCHEMA_VERSION:
        raise _error("E_MANIFEST_INVALID", "unsupported manifest schema")
    release = data.get("release")
    modes = data.get("modes")
    if not isinstance(release, dict) or not isinstance(modes, dict):
        raise _error("E_MANIFEST_INVALID", "manifest release and modes are required")
    for field in ("source", "ref", "commit", "runtime_version"):
        if not isinstance(release.get(field), str) or not release[field]:
            raise _error("E_MANIFEST_INVALID", "manifest release metadata is incomplete")
    _approved_url(release["source"])
    _validate_ref(release["ref"])
    if not COMMIT_RE.fullmatch(release["commit"]):
        raise _error("E_MANIFEST_INVALID", "manifest commit is not a 40-hex value")
    if expected_ref and release["ref"] != expected_ref:
        raise _error("E_MANIFEST_INVALID", "manifest ref does not match requested ref")
    for mode, item in modes.items():
        if mode not in MODES or not isinstance(item, dict):
            raise _error("E_MANIFEST_INVALID", "manifest contains an unknown mode")
        url = item.get("archive_url")
        digest = item.get("archive_sha256")
        size = item.get("archive_size")
        entries = item.get("entrypoints")
        if not isinstance(url, str) or not isinstance(digest, str) or not isinstance(size, int):
            raise _error("E_MANIFEST_INVALID", "archive metadata is incomplete")
        if not SHA256_RE.fullmatch(digest) or size < 1 or size > MAX_ARCHIVE_BYTES:
            raise _error("E_MANIFEST_INVALID", "archive digest or size is invalid")
        if not isinstance(entries, dict) or not entries:
            raise _error("E_MANIFEST_INVALID", "entrypoints are required")
        for key, entry in entries.items():
            if key not in SLOTS:
                raise _error("E_MANIFEST_INVALID", "entrypoint key is invalid")
            _validate_relative(entry)
        if set(entries) != MODE_SLOTS[mode]:
            raise _error("E_MANIFEST_INVALID", "manifest entrypoints do not match mode events")
        _approved_url(url)
    if set(modes) != set(MODES):
        raise _error("E_MANIFEST_INVALID", "manifest must describe all four modes")
    return data


def validate_identity(identity: Mapping[str, Any]) -> Dict[str, Any]:
    """在 selector/index 資料成為 cache 或程序輸入前先完成驗證。"""
    required = {
        "schema_version", "mode", "source", "ref", "commit", "runtime_version",
        "archive_url", "archive_sha256", "archive_size", "entrypoints",
    }
    if not isinstance(identity, dict) or set(identity) != required or identity.get("schema_version") != 1:
        raise _error("E_CACHE_CORRUPT", "runtime identity schema is invalid")
    mode = identity.get("mode")
    if mode not in MODES or identity.get("source") not in ("github", "development", "local", "test"):
        raise _error("E_CACHE_CORRUPT", "runtime identity mode or source is invalid")
    _validate_ref(identity.get("ref"))
    if not isinstance(identity.get("runtime_version"), str) or not identity["runtime_version"]:
        raise _error("E_CACHE_CORRUPT", "runtime version is invalid")
    if not COMMIT_RE.fullmatch(str(identity.get("commit"))):
        raise _error("E_CACHE_CORRUPT", "runtime identity commit is invalid")
    _approved_url(identity.get("archive_url"))
    if not SHA256_RE.fullmatch(str(identity.get("archive_sha256"))):
        raise _error("E_CACHE_CORRUPT", "runtime identity digest is invalid")
    if not isinstance(identity.get("archive_size"), int) or not 1 <= identity["archive_size"] <= MAX_ARCHIVE_BYTES:
        raise _error("E_CACHE_CORRUPT", "runtime identity archive size is invalid")
    entries = identity.get("entrypoints")
    if not isinstance(entries, dict) or set(entries) != MODE_SLOTS[mode]:
        raise _error("E_CACHE_CORRUPT", "runtime identity entrypoints are invalid")
    for entry in entries.values():
        _validate_relative(entry)
    return dict(identity)


def validate_archive(archive: bytes, expected_digest: str, expected_size: int) -> str:
    if len(archive) != expected_size or len(archive) > MAX_ARCHIVE_BYTES:
        raise _error("E_DIGEST_MISMATCH", "archive size does not match manifest")
    digest = hashlib.sha256(archive).hexdigest()
    if digest != expected_digest:
        raise _error("E_DIGEST_MISMATCH", "archive SHA-256 does not match manifest")
    return digest


def _archive_member_path(name: str) -> str:
    try:
        name.encode("utf-8").decode("utf-8")
    except UnicodeError:
        raise _error("E_ARCHIVE_UNSAFE", "archive name is not UTF-8")
    if not name or "\x00" in name or "\\" in name or name.startswith("/"):
        raise _error("E_ARCHIVE_UNSAFE", "archive contains an unsafe path")
    if re.match(r"^[A-Za-z]:", name) or name.startswith("//"):
        raise _error("E_ARCHIVE_UNSAFE", "archive contains a drive or UNC path")
    parts = name.split("/")
    if any(not part or part in (".", "..") for part in parts):
        raise _error("E_ARCHIVE_UNSAFE", "archive contains an unsafe path segment")
    normalized = posixpath.normpath(name)
    if normalized != name:
        raise _error("E_ARCHIVE_UNSAFE", "archive contains a non-normalized path")
    return name


def extract_verified_archive(archive: bytes, destination: Path, entrypoints: Mapping[str, str]) -> None:
    _safe_path(destination, parent=True)
    destination.mkdir(parents=True, exist_ok=False)
    seen: set = set()
    extracted = 0
    try:
        with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as bundle:
            members = bundle.getmembers()
            if len(members) > MAX_ARCHIVE_FILES:
                raise _error("E_ARCHIVE_UNSAFE", "archive contains too many files")
            for member in members:
                name = _archive_member_path(member.name)
                if name in seen:
                    raise _error("E_ARCHIVE_UNSAFE", "archive contains duplicate paths")
                seen.add(name)
                if member.issym() or member.islnk() or member.isdev() or not member.isreg():
                    raise _error("E_ARCHIVE_UNSAFE", "archive contains a non-regular file")
                if member.size < 0:
                    raise _error("E_ARCHIVE_UNSAFE", "archive member size is invalid")
                extracted += member.size
                if extracted > MAX_EXTRACTED_BYTES:
                    raise _error("E_ARCHIVE_UNSAFE", "archive expands beyond size limit")
                target = destination.joinpath(*PurePosixPath(name).parts)
                _ensure_contained(destination, target)
                target.parent.mkdir(parents=True, exist_ok=True)
                if target.parent.is_symlink() or target.exists():
                    raise _error("E_ARCHIVE_UNSAFE", "archive extraction escaped or collided")
                source = bundle.extractfile(member)
                if source is None:
                    raise _error("E_ARCHIVE_UNSAFE", "archive member cannot be read")
                written = 0
                with target.open("xb") as output:
                    while True:
                        chunk = source.read(1024 * 1024)
                        if not chunk:
                            break
                        written += len(chunk)
                        if written > member.size:
                            raise _error("E_ARCHIVE_UNSAFE", "archive member exceeds declared size")
                        output.write(chunk)
                if written != member.size:
                    raise _error("E_ARCHIVE_UNSAFE", "archive member is truncated")
        for entry in entrypoints.values():
            target = destination.joinpath(*PurePosixPath(_validate_relative(entry)).parts)
            if not target.is_file() or target.is_symlink():
                raise _error("E_ARCHIVE_UNSAFE", "manifest entrypoint is not a regular file")
    except ManagerError:
        shutil.rmtree(destination, ignore_errors=True)
        raise
    except (OSError, tarfile.TarError):
        shutil.rmtree(destination, ignore_errors=True)
        raise _error("E_ARCHIVE_UNSAFE", "archive cannot be safely extracted")


class ManifestSource:
    development = False

    def fetch_manifest(self, ref: str) -> bytes:
        raise NotImplementedError

    def fetch_archive(self, url: str) -> bytes:
        raise NotImplementedError


class HttpsManifestSource(ManifestSource):
    def __init__(self, base: str = "https://raw.githubusercontent.com/ashiyasayo/ai-guardrail-kit"):
        self.base = base.rstrip("/")

    @staticmethod
    def _approved(url: str) -> urllib.parse.ParseResult:
        return _approved_url(url)

    def _get(self, url: str, limit: int) -> bytes:
        opener = urllib.request.build_opener(_NoRedirect())
        for _ in range(4):
            self._approved(url)
            request = urllib.request.Request(url, headers={"User-Agent": "ai-guardrail-kit"})
            try:
                with opener.open(request, timeout=20) as response:
                    if response.status in (301, 302, 303, 307, 308):
                        location = response.headers.get("Location")
                        if not location:
                            raise _error("E_NETWORK", "redirect has no location")
                        url = urllib.parse.urljoin(url, location)
                        continue
                    data = response.read(limit + 1)
                    if len(data) > limit:
                        raise _error("E_NETWORK", "download exceeds size limit")
                    return data
            except ManagerError:
                raise
            except urllib.error.HTTPError as error:
                if error.code in (301, 302, 303, 307, 308):
                    location = error.headers.get("Location")
                    if not location:
                        raise _error("E_NETWORK", "redirect has no location")
                    url = urllib.parse.urljoin(url, location)
                    continue
                raise _error("E_NETWORK", "approved HTTPS source is unavailable")
            except (OSError, urllib.error.URLError):
                raise _error("E_NETWORK", "approved HTTPS source is unavailable")
        raise _error("E_NETWORK", "too many redirects")

    def fetch_manifest(self, ref: str) -> bytes:
        return self._get(self.base + "/" + ref + "/codex/runtime-manifest.json", MAX_MANIFEST_BYTES)

    def fetch_archive(self, url: str) -> bytes:
        return self._get(url, MAX_ARCHIVE_BYTES)


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req: Any, fp: Any, code: int, msg: str, headers: Any, newurl: str) -> Any:
        return None


class FileManifestSource(ManifestSource):
    """明確的開發 adapter；不由不受信任的 URL 選用。"""
    development = True

    def __init__(self, manifest_path: Path, archive_dir: Optional[Path] = None):
        self.manifest_path = manifest_path
        self.archive_dir = archive_dir

    def fetch_manifest(self, ref: str) -> bytes:
        try:
            return self.manifest_path.read_bytes()
        except OSError:
            raise _error("E_NETWORK", "development manifest is unavailable")

    def fetch_archive(self, url: str) -> bytes:
        name = Path(urllib.parse.urlparse(url).path).name
        if self.archive_dir is None or not name:
            raise _error("E_SOURCE_DENIED", "development archive directory is not configured")
        try:
            return (self.archive_dir / name).read_bytes()
        except OSError:
            raise _error("E_NETWORK", "development archive is unavailable")


class MemoryManifestSource(ManifestSource):
    """供測試使用的 adapter，提供決定性的 manifest/archive 與離線測試。"""
    development = True

    def __init__(self, manifest: Mapping[str, Any], archives: Mapping[str, bytes]):
        self.manifest = _json_bytes(dict(manifest))
        self.archives = dict(archives)
        self.calls: List[str] = []

    def fetch_manifest(self, ref: str) -> bytes:
        self.calls.append("manifest")
        return self.manifest

    def fetch_archive(self, url: str) -> bytes:
        self.calls.append("archive")
        try:
            return self.archives[url]
        except KeyError:
            raise _error("E_NETWORK", "test archive is unavailable")


class HookProcess:
    def run(self, python: str, entrypoint: Path, event: bytes, environment: Mapping[str, str]) -> Tuple[int, bytes, bytes]:
        raise NotImplementedError


class SubprocessHookProcess(HookProcess):
    def __init__(self, timeout: float = 15.0):
        self.timeout = timeout

    def run(self, python: str, entrypoint: Path, event: bytes, environment: Mapping[str, str]) -> Tuple[int, bytes, bytes]:
        try:
            result = subprocess.run([python, "--", str(entrypoint)], input=event, capture_output=True,
                                    timeout=self.timeout, env=dict(environment), shell=False)
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise _error("E_HOOK_FAILED", "runtime hook could not complete") from exc
        if len(result.stdout) > MAX_OUTPUT_BYTES or len(result.stderr) > MAX_OUTPUT_BYTES:
            raise _error("E_HOOK_FAILED", "runtime hook output exceeds limit")
        return result.returncode, result.stdout, result.stderr


class RuntimeStore:
    def __init__(self, codex_home: Path):
        self.root = codex_home / "guardrail"
        self.cache = self.root / "runtime-cache" / "sha256"
        self.index = self.root / "runtime-index.json"
        self.selector_registry = self.root / "selector-index.json"

    def selector_path(self, scope: str, project: Path) -> Path:
        if scope == "project":
            return project / ".codex" / "guardrail" / "runtime.json"
        if scope == "local":
            return project / ".codex" / "guardrail" / "runtime.local.json"
        if scope == "user":
            return self.root / "default-runtime.json"
        raise _error("E_USAGE", "unsupported selector scope")

    def cache_path(self, digest: str) -> Path:
        if not SHA256_RE.fullmatch(digest):
            raise _error("E_CACHE_CORRUPT", "invalid cache digest")
        return self.cache / digest

    def verify_cache(self, identity: Mapping[str, Any]) -> Path:
        identity = validate_identity(identity)
        location = self.cache_path(str(identity["archive_sha256"]))
        _safe_path(location)
        metadata = _read_json(location / "runtime.json")
        if metadata.get("complete") is not True or metadata.get("identity") != dict(identity):
            raise _error("E_CACHE_CORRUPT", "runtime cache identity is incomplete")
        payload = location / "payload"
        expected_files = metadata.get("payload_files")
        if not isinstance(expected_files, dict):
            raise _error("E_CACHE_CORRUPT", "runtime payload index is missing")
        _safe_path(payload)
        if not payload.is_dir() or payload.is_symlink():
            raise _error("E_CACHE_CORRUPT", "runtime payload directory is missing")
        actual_files: Dict[str, Dict[str, Any]] = {}
        for base, dirs, files in os.walk(payload, topdown=True, followlinks=False):
            base_path = Path(base)
            if any((base_path / name).is_symlink() for name in dirs):
                raise _error("E_CACHE_CORRUPT", "runtime payload contains a symlink")
            for name in files:
                target = base_path / name
                if target.is_symlink() or not target.is_file():
                    raise _error("E_CACHE_CORRUPT", "runtime payload contains a non-regular file")
                relative = target.relative_to(payload).as_posix()
                actual_files[relative] = {"sha256": hashlib.sha256(target.read_bytes()).hexdigest(), "size": target.stat().st_size}
        if actual_files != expected_files:
            raise _error("E_CACHE_CORRUPT", "runtime payload digest does not match metadata")
        for entry in identity["entrypoints"].values():
            target = payload.joinpath(*PurePosixPath(entry).parts)
            _ensure_contained(payload, target)
            if not target.is_file() or target.is_symlink():
                raise _error("E_CACHE_CORRUPT", "runtime entrypoint is missing")
        return payload

    def install(self, identity: Dict[str, Any], archive: bytes) -> Tuple[Path, bool]:
        identity = validate_identity(identity)
        destination = self.cache_path(identity["archive_sha256"])
        if destination.exists() or destination.is_symlink():
            try:
                return self.verify_cache(identity), True
            except ManagerError as error:
                if error.code != "E_CACHE_CORRUPT":
                    raise
        _safe_path(self.cache, parent=True)
        self.cache.mkdir(parents=True, exist_ok=True)
        if self.cache.is_symlink() or not self.cache.is_dir():
            raise _error("E_SCOPE_UNSAFE", "runtime cache is not a real directory")
        lock = self.cache / (identity["archive_sha256"] + ".lock")
        _safe_path(lock, parent=True)
        if lock.is_symlink():
            raise _error("E_SCOPE_UNSAFE", "runtime cache lock is a symlink")
        acquired = False
        deadline = time.monotonic() + 30
        while not acquired:
            try:
                fd = os.open(str(lock), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
                os.close(fd)
                acquired = True
            except FileExistsError:
                if time.monotonic() >= deadline:
                    raise _error("E_CACHE_CORRUPT", "runtime cache lock timed out")
                time.sleep(0.05)
        if destination.exists():
            try:
                return self.verify_cache(identity), True
            except ManagerError as error:
                if error.code != "E_CACHE_CORRUPT":
                    raise
                _safe_path(destination)
                quarantine = destination.with_name(destination.name + ".corrupt-" + uuid.uuid4().hex[:8])
                os.replace(str(destination), str(quarantine))
        staging: Optional[Path] = None
        try:
            staging = Path(tempfile.mkdtemp(prefix=".runtime-", dir=str(self.cache)))
            extract_verified_archive(archive, staging / "payload", identity["entrypoints"])
            files: Dict[str, Dict[str, Any]] = {}
            payload = staging / "payload"
            for base, dirs, names in os.walk(payload, topdown=True, followlinks=False):
                base_path = Path(base)
                if any((base_path / name).is_symlink() for name in dirs):
                    raise _error("E_ARCHIVE_UNSAFE", "runtime payload contains a symlink")
                for name in names:
                    target = base_path / name
                    if target.is_symlink() or not target.is_file():
                        raise _error("E_ARCHIVE_UNSAFE", "runtime payload is not regular")
                    relative = target.relative_to(payload).as_posix()
                    files[relative] = {"sha256": hashlib.sha256(target.read_bytes()).hexdigest(), "size": target.stat().st_size}
            _atomic_write(staging / "runtime.json", _json_bytes({"schema_version": 1, "identity": identity, "payload_files": files, "complete": True}))
            os.replace(str(staging), str(destination))
            self.verify_cache(identity)
        except BaseException:
            if staging is not None:
                shutil.rmtree(staging, ignore_errors=True)
            raise
        finally:
            try:
                lock.unlink()
            except OSError:
                pass
        return destination / "payload", False


LOADER_MARKER = "AI_GUARDRAIL_LOADER=1 "
LOADER_COMMAND_RE = re.compile(r"^AI_GUARDRAIL_LOADER_SLOT=[a-z.]+ " + re.escape(LOADER_MARKER))
LOADER_WINDOWS_COMMAND_RE = re.compile(
    r"^\$env:AI_GUARDRAIL_LOADER_SLOT = '[a-z.]+'; "
    r"\$env:AI_GUARDRAIL_LOADER = '1'; "
)
LOADER_VERSION = "1.0.0"
LEGACY_MARKERS = (
    "AI_GUARDRAIL_GLOBAL_DEFAULT=1 ",
    "AI_GUARDRAIL_LOCAL_DEFAULT=1 ",
    "AI_GUARDRAIL_USER_DEFAULT=1 ",
)
LEGACY_SPECS = {
    "decomposition-gate": (("PreToolUse", "exec_command|apply_patch", "decomposition_gate.py"),),
    "sensitive-data-guard": (
        ("PreToolUse", "exec_command|apply_patch", "block_secrets.py"),
        ("PreToolUse", "apply_patch", "pii_guard.py"),
        ("UserPromptSubmit", None, "pii_guard.py"),
    ),
    "harness": (
        ("PreToolUse", "exec_command|apply_patch", "plan_gate.py"),
        ("PreToolUse", "exec_command|apply_patch", "security_guard.py"),
        ("PreToolUse", "apply_patch", "pii_guard.py"),
        ("UserPromptSubmit", None, "pii_guard.py"),
    ),
    "integrated-harness": (
        ("PreToolUse", "exec_command|apply_patch", "plan_gate.py"),
        ("PreToolUse", "exec_command|apply_patch", "security_guard.py"),
        ("PreToolUse", "apply_patch", "pii_guard.py"),
        ("UserPromptSubmit", None, "pii_guard.py"),
        ("SessionStart", "startup|resume|clear|compact", "session_start.py"),
    ),
}


def _read_regular_bytes(path: Path) -> bytes:
    _safe_path(path)
    if not path.is_file() or path.is_symlink():
        raise _error("E_SCOPE_UNSAFE", "managed file is not a regular file")
    try:
        return path.read_bytes()
    except (OSError, UnicodeError) as exc:
        raise _error("E_SCOPE_UNSAFE", "managed file cannot be read") from exc


def _is_loader_command(command: Any) -> bool:
    return (isinstance(command, str)
            and (command.startswith(LOADER_MARKER)
                 or LOADER_COMMAND_RE.match(command) is not None
                 or LOADER_WINDOWS_COMMAND_RE.match(command) is not None))


def _legacy_command_matches(command: str) -> List[Tuple[str, str]]:
    normalized = command.replace("\\", "/")
    matches: List[Tuple[str, str]] = []
    pattern = re.compile(r"(?:^|/)codex/plugins/([a-z0-9-]+)/hooks/([^/'\"\s]+)")
    for match in pattern.finditer(normalized):
        pair = (match.group(1), match.group(2))
        if pair not in matches:
            matches.append(pair)
    return matches


def _legacy_mode_from_paths(paths: Sequence[str]) -> str:
    if not paths:
        raise _error("E_LEGACY_AMBIGUOUS", "legacy hook set is incomplete or malformed")
    detected: List[Tuple[str, str]] = []
    for command in paths:
        matches = _legacy_command_matches(command)
        if len(matches) != 1:
            raise _error("E_LEGACY_AMBIGUOUS", "legacy hook mode cannot be determined")
        mode, filename = matches[0]
        if mode not in MODES:
            raise _error("E_LEGACY_AMBIGUOUS", "legacy hook points to an unknown mode")
        detected.append((mode, filename))
    modes = {mode for mode, _ in detected}
    if len(modes) != 1:
        raise _error("E_LEGACY_AMBIGUOUS", "legacy hooks mix multiple modes")
    mode = next(iter(modes))
    expected_files = Counter(filename for _, _, filename in LEGACY_SPECS[mode])
    actual_files = Counter(filename for _, filename in detected)
    if actual_files != expected_files:
        raise _error("E_LEGACY_AMBIGUOUS", "legacy hook set is incomplete or malformed")
    return mode


def _collect_legacy_hook_specs(hooks: Mapping[str, Any], prefixes: Sequence[str]) -> List[Tuple[str, Optional[str], str]]:
    specs: List[Tuple[str, Optional[str], str]] = []
    for event, rules in hooks.items():
        if not isinstance(rules, list):
            raise _error("E_SCOPE_UNSAFE", "user hooks event must contain an array")
        for rule in rules:
            if not isinstance(rule, dict) or not isinstance(rule.get("hooks", []), list):
                raise _error("E_SCOPE_UNSAFE", "user hooks rule is invalid")
            for entry in rule["hooks"]:
                command = entry.get("command") if isinstance(entry, dict) else None
                if isinstance(command, str) and command.startswith(tuple(prefixes)):
                    specs.append((event, rule.get("matcher"), command))
    return specs


def _legacy_mode_from_hooks(hooks: Mapping[str, Any], prefixes: Sequence[str]) -> Optional[str]:
    specs = _collect_legacy_hook_specs(hooks, prefixes)
    if not specs:
        return None
    actual = []
    detected_modes = []
    for event, matcher, command in specs:
        matches = _legacy_command_matches(command)
        if len(matches) != 1:
            raise _error("E_LEGACY_AMBIGUOUS", "legacy hook mode cannot be determined")
        mode, filename = matches[0]
        actual.append((event, matcher, filename))
        detected_modes.append(mode)
        if mode not in MODES:
            raise _error("E_LEGACY_AMBIGUOUS", "legacy hook points to an unknown mode")
    modes = set(detected_modes)
    if len(modes) != 1:
        raise _error("E_LEGACY_AMBIGUOUS", "legacy hooks mix multiple modes")
    mode = next(iter(modes))
    if Counter(actual) != Counter(LEGACY_SPECS[mode]):
        raise _error("E_LEGACY_AMBIGUOUS", "legacy hook set is incomplete or malformed")
    return mode


def _legacy_config_migration(path: Path) -> Optional[Dict[str, Any]]:
    if not path.exists():
        return None
    old = _read_regular_bytes(path)
    lines = old.splitlines(keepends=True)
    begin = b"# ai-guardrail-kit:begin"
    end = b"# ai-guardrail-kit:end"
    begin_positions = []
    end_positions = []
    offset = 0
    for line in lines:
        content = line.rstrip(b"\r\n")
        if content == begin:
            begin_positions.append(offset)
        if content == end:
            end_positions.append(offset + len(line))
        offset += len(line)
    if not begin_positions and not end_positions:
        return None
    if len(begin_positions) != 1 or len(end_positions) != 1 or end_positions[0] <= begin_positions[0]:
        raise _error("E_LEGACY_AMBIGUOUS", "legacy TOML managed block is malformed")
    start, finish = begin_positions[0], end_positions[0]
    try:
        block = old[start:finish].decode("utf-8")
    except UnicodeDecodeError as exc:
        raise _error("E_LEGACY_AMBIGUOUS", "legacy TOML managed block is not UTF-8") from exc
    commands = re.findall(r'^\s*command\s*=\s*"([^"]+)"', block, flags=re.MULTILINE)
    _legacy_mode_from_paths(commands)
    return {"path": path, "old": old, "new": old[:start] + old[finish:]}


def _legacy_hooks_migration(path: Path, prefixes: Sequence[str]) -> Optional[Dict[str, Any]]:
    if not path.exists():
        return None
    old = _read_regular_bytes(path)
    data = _read_json(path)
    hooks = data.get("hooks", {})
    if not isinstance(hooks, dict):
        raise _error("E_SCOPE_UNSAFE", "user hooks must contain an object")
    if _legacy_mode_from_hooks(hooks, prefixes) is None:
        return None
    for event, rules in list(hooks.items()):
        kept_rules = []
        for rule in rules:
            kept = [entry for entry in rule["hooks"]
                    if not (isinstance(entry, dict) and isinstance(entry.get("command"), str)
                            and entry["command"].startswith(tuple(prefixes)))]
            if kept:
                updated = dict(rule)
                updated["hooks"] = kept
                kept_rules.append(updated)
        hooks[event] = kept_rules
    return {"path": path, "old": old, "new": _json_bytes(data)}


def prepare_legacy_migrations(store: RuntimeStore, project: Path, scope: str) -> List[Dict[str, Any]]:
    if scope == "project":
        migration = _legacy_config_migration(project / ".codex" / "config.toml")
        return [migration] if migration else []
    if scope == "local":
        migration = _legacy_hooks_migration(project / ".codex" / "hooks.json", ("AI_GUARDRAIL_LOCAL_DEFAULT=1 ",))
        return [migration] if migration else []
    migration = _legacy_hooks_migration(store.root.parent / "hooks.json", ("AI_GUARDRAIL_USER_DEFAULT=1 ", "AI_GUARDRAIL_GLOBAL_DEFAULT=1 "))
    return [migration] if migration else []


def loader_is_installed(store: RuntimeStore) -> bool:
    current = store.root / "loader" / "current.json"
    stable = store.root / "loader" / "loader.py"
    manager = store.root / "loader" / "manager.py"
    try:
        data = _read_json(current)
        _safe_path(stable)
        _safe_path(manager)
    except ManagerError:
        return False
    return data.get("schema_version") == 1 and data.get("complete") is True and stable.is_file() and manager.is_file()


def _powershell_quote(value: str) -> str:
    """PowerShell 單引號字串只需將單引號重複，避免路徑被當成程式碼。"""
    return "'" + value.replace("'", "''") + "'"


def _loader_hook_command(python: str, loader: Path, slot: str, windows: bool) -> str:
    if windows:
        # Codex Windows hook 由 PowerShell 執行；直接設定環境變數可保留 stdin 並避免 Bash 語法失效。
        return ("$env:AI_GUARDRAIL_LOADER_SLOT = " + _powershell_quote(slot)
                + "; $env:AI_GUARDRAIL_LOADER = '1'; & " + _powershell_quote(python)
                + " -- " + _powershell_quote(str(loader)))
    return ("AI_GUARDRAIL_LOADER_SLOT=" + slot + " " + LOADER_MARKER
            + shlex.quote(python) + " -- " + shlex.quote(str(loader)))


def _loader_hook_data(path: Path, python: str, action: str) -> Dict[str, Any]:
    if path.exists():
        data = _read_json(path)
    else:
        data = {"hooks": {}}
    hooks = data.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        raise _error("E_SCOPE_UNSAFE", "user hooks must contain an object")
    # 只在整組 legacy hook 可辨識時遷移，避免把殘缺或混合設定靜默刪掉。
    _legacy_mode_from_hooks(hooks, LEGACY_MARKERS)
    for event, rules in list(hooks.items()):
        if not isinstance(rules, list):
            raise _error("E_SCOPE_UNSAFE", "user hooks event must contain an array")
        kept = []
        for rule in rules:
            if not isinstance(rule, dict) or not isinstance(rule.get("hooks", []), list):
                raise _error("E_SCOPE_UNSAFE", "user hooks rule is invalid")
            entries = [entry for entry in rule["hooks"]
                       if not (isinstance(entry, dict) and isinstance(entry.get("command"), str)
                               and (_is_loader_command(entry["command"])
                                    or entry["command"].startswith(tuple(LEGACY_MARKERS))))]
            if entries:
                copy = dict(rule)
                copy["hooks"] = entries
                kept.append(copy)
        hooks[event] = kept
    if action == "install":
        loader = path.parent / "guardrail" / "loader" / "loader.py"
        specs = [
            ("PreToolUse", "exec_command|apply_patch", "pretool.decomposition"),
            ("PreToolUse", "exec_command|apply_patch", "pretool.plan"),
            ("PreToolUse", "exec_command|apply_patch", "pretool.security"),
            ("PreToolUse", "apply_patch", "pretool.pii"),
            ("UserPromptSubmit", None, "prompt.pii"),
            ("SessionStart", "startup|resume|clear|compact", "session.start"),
        ]
        for event, matcher, slot in specs:
            command = _loader_hook_command(python, loader, slot, os.name == "nt")
            rule = {"hooks": [{"type": "command", "command": command}]}
            if matcher:
                rule["matcher"] = matcher
            hooks.setdefault(event, []).append(rule)
    return data


LOADER_PLUGIN_ID = "ai-guardrail-loader@ai-guardrail-kit"


def _run_codex_plugin(action: str) -> None:
    codex = shutil.which("codex")
    if not codex:
        raise _error("E_HOOK_FAILED", "Codex CLI is unavailable")
    command = [codex, "plugin", action, LOADER_PLUGIN_ID]
    # Windows 的測試 fake 是 Bash script；正式 Codex 通常是 exe/cmd，仍維持 shell=False。
    if os.name == "nt" and Path(codex).suffix.lower() not in (".exe", ".cmd", ".bat"):
        bash = shutil.which("bash")
        if bash:
            command = [bash, codex, "plugin", action, LOADER_PLUGIN_ID]
    try:
        result = subprocess.run(command, capture_output=True, timeout=30, shell=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise _error("E_HOOK_FAILED", "Codex plugin operation failed") from exc
    if result.returncode != 0:
        raise _error("E_HOOK_FAILED", "Codex plugin operation failed")


def install_loader(repo: Optional[Path], plugin_root: Optional[Path], update: bool = False, remove: bool = False) -> None:
    home = codex_home()
    root = home / "guardrail" / "loader"
    stable = root / "loader.py"
    stable_manager = root / "manager.py"
    current = root / "current.json"
    hooks = home / "hooks.json"
    plugin = plugin_root or (repo / "codex" / "plugins" / "ai-guardrail-loader" if repo else None)
    if plugin is None:
        raise _error("E_RUNTIME_MISSING", "loader plugin root is unavailable")
    source_loader = plugin / "hooks" / "loader.py"
    source_manager = plugin / "hooks" / "manager.py"
    if not source_manager.is_file() and repo:
        source_manager = repo / "scripts" / "codex-runtime-manager.py"
    bin_dir = home / "guardrail" / "bin"
    release = root / "releases" / LOADER_VERSION
    managed_paths = [
        release / "loader.py", release / "manager.py", stable, stable_manager, current,
        bin_dir / "select-codex-mode", bin_dir / "verify-codex-mode",
        bin_dir / "install-codex-guardrail-loader", bin_dir / "prune-codex-runtime-cache",
        bin_dir / "codex-runtime-manager.py", hooks,
    ]
    snapshots: Dict[Path, Optional[Tuple[bytes, int]]] = {}
    for path in managed_paths:
        if path.exists() or path.is_symlink():
            content = snapshot_managed_file(path)
            snapshots[path] = (content, path.stat().st_mode & 0o777)
        else:
            snapshots[path] = None

    def rollback_files() -> None:
        errors: List[BaseException] = []
        for path in reversed(managed_paths):
            snapshot = snapshots[path]
            try:
                if snapshot is None:
                    _remove_managed_file(path)
                else:
                    _atomic_write(path, snapshot[0], snapshot[1])
            except BaseException as error:
                errors.append(error)
        if errors:
            raise _error("E_ROLLBACK_FAILED", "loader transaction rollback failed") from errors[0]
    if remove:
        if _referenced_runtime_digests(RuntimeStore(home)):
            raise _error("E_SCOPE_UNSAFE", "loader is still referenced by a selector")
        plugin_removed = False
        try:
            _run_codex_plugin("remove")
            plugin_removed = True
            if hooks.exists():
                data = _loader_hook_data(hooks, sys.executable, "remove")
                _atomic_write(hooks, _json_bytes(data), hooks.stat().st_mode & 0o777)
            for path in (current, stable, stable_manager, release / "loader.py", release / "manager.py",
                         bin_dir / "select-codex-mode", bin_dir / "verify-codex-mode",
                         bin_dir / "install-codex-guardrail-loader", bin_dir / "prune-codex-runtime-cache",
                         bin_dir / "codex-runtime-manager.py"):
                _remove_managed_file(path)
        except BaseException as error:
            try:
                rollback_files()
                if plugin_removed:
                    _run_codex_plugin("add")
            except BaseException as rollback:
                raise _error("E_ROLLBACK_FAILED", "loader uninstall rollback failed") from rollback
            raise error
        return
    if not source_loader.is_file() or not source_manager.is_file():
        raise _error("E_RUNTIME_MISSING", "loader sources are unavailable")
    try:
        _safe_path(root, parent=True)
        root.mkdir(parents=True, exist_ok=True)
        if root.is_symlink() or not root.is_dir():
            raise _error("E_SCOPE_UNSAFE", "loader directory is not real")
        _safe_path(release, parent=True)
        release.mkdir(parents=True, exist_ok=True)
        if release.is_symlink() or not release.is_dir():
            raise _error("E_SCOPE_UNSAFE", "loader release directory is not real")
        _atomic_write(release / "loader.py", source_loader.read_bytes())
        _atomic_write(release / "manager.py", source_manager.read_bytes())
        _atomic_write(stable, source_loader.read_bytes())
        _atomic_write(stable_manager, source_manager.read_bytes())
        _safe_path(bin_dir, parent=True)
        bin_dir.mkdir(parents=True, exist_ok=True)
        if bin_dir.is_symlink() or not bin_dir.is_dir():
            raise _error("E_SCOPE_UNSAFE", "loader bin directory is not real")
        for name in ("select-codex-mode", "verify-codex-mode", "install-codex-guardrail-loader",
                     "prune-codex-runtime-cache"):
            source = plugin / "hooks" / name
            if source.is_file():
                _atomic_write(bin_dir / name, source.read_bytes(), 0o755)
        _atomic_write(bin_dir / "codex-runtime-manager.py", source_manager.read_bytes(), 0o644)
        _atomic_write(current, _json_bytes({"schema_version": 1, "loader_version": LOADER_VERSION, "entrypoint": "loader.py", "complete": True}))
        if os.environ.get("AI_GUARDRAIL_TEST_FAIL_LOADER_HOOKS") == "1":
            raise _error("E_HOOK_FAILED", "test-injected loader hook failure")
        data = _loader_hook_data(hooks, sys.executable, "install")
        _atomic_write(hooks, _json_bytes(data), hooks.stat().st_mode & 0o777 if hooks.exists() else None)
        _run_codex_plugin("add")
    except BaseException as error:
        try:
            rollback_files()
        except BaseException as rollback:
            raise rollback
        raise error


def codex_home() -> Path:
    return Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex"))).resolve()


def select_source(name: str) -> ManifestSource:
    if name in ("github", ""):
        return HttpsManifestSource()
    if name in ("local", "test") and os.environ.get("AI_GUARDRAIL_ALLOW_DEVELOPMENT_SOURCE") == "1":
        manifest = os.environ.get("AI_GUARDRAIL_MANIFEST_PATH")
        archive_dir = os.environ.get("AI_GUARDRAIL_ARCHIVE_DIR")
        if not manifest:
            raise _error("E_SOURCE_DENIED", "development source requires AI_GUARDRAIL_MANIFEST_PATH")
        return FileManifestSource(Path(manifest), Path(archive_dir) if archive_dir else None)
    raise _error("E_SOURCE_DENIED", "source alias is not approved")


def identity_from_manifest(manifest: Mapping[str, Any], mode: str, source: str) -> Dict[str, Any]:
    item = manifest["modes"][mode]
    return validate_identity({
        "schema_version": 1,
        "mode": mode,
        "source": source,
        "ref": manifest["release"]["ref"],
        "commit": manifest["release"]["commit"],
        "runtime_version": manifest["release"]["runtime_version"],
        "archive_url": item["archive_url"],
        "archive_sha256": item["archive_sha256"],
        "archive_size": item["archive_size"],
        "entrypoints": dict(item["entrypoints"]),
    })


def _load_selector(store: RuntimeStore, path: Path, expected_scope: Optional[str] = None) -> Dict[str, Any]:
    data = _read_json(path)
    if data.get("schema_version") != 1 or data.get("scope") not in SCOPES or data.get("mode") not in MODES:
        raise _error("E_CACHE_CORRUPT", "selector schema is invalid")
    if data.get("owner") not in (None, "global-integrated-harness"):
        raise _error("E_CACHE_CORRUPT", "selector owner is invalid")
    if expected_scope is not None and data.get("scope") != expected_scope:
        raise _error("E_CACHE_CORRUPT", "selector scope does not match its location")
    identity = data.get("identity")
    if not isinstance(identity, dict) or identity.get("mode") != data["mode"]:
        raise _error("E_CACHE_CORRUPT", "selector identity is invalid")
    validate_identity(identity)
    return data


def _selector_identity(store: RuntimeStore, path: Path, expected_scope: Optional[str] = None) -> Tuple[Dict[str, Any], Path]:
    data = _load_selector(store, path, expected_scope)
    return data["identity"], store.verify_cache(data["identity"])


def _registry_selector_path(store: RuntimeStore, entry: Mapping[str, Any]) -> Path:
    if set(entry) != {"path", "scope", "archive_sha256"}:
        raise _error("E_CACHE_CORRUPT", "selector registry entry is invalid")
    scope = entry.get("scope")
    raw_path = entry.get("path")
    if scope not in SCOPES or not isinstance(raw_path, str):
        raise _error("E_CACHE_CORRUPT", "selector registry entry is invalid")
    if not SHA256_RE.fullmatch(str(entry.get("archive_sha256"))):
        raise _error("E_CACHE_CORRUPT", "selector registry digest is invalid")
    path = Path(raw_path)
    if not path.is_absolute():
        raise _error("E_CACHE_CORRUPT", "selector registry path is not absolute")
    _safe_path(path)
    if scope == "user":
        expected = store.selector_path("user", Path.cwd()).resolve(strict=False)
        if path.resolve(strict=False) != expected:
            raise _error("E_CACHE_CORRUPT", "selector registry user path is invalid")
    else:
        expected_name = "runtime.json" if scope == "project" else "runtime.local.json"
        if (path.name != expected_name or path.parent.name != "guardrail"
                or path.parent.parent.name != ".codex"):
            raise _error("E_CACHE_CORRUPT", "selector registry project path is invalid")
    return path


def _read_selector_registry(store: RuntimeStore) -> List[Dict[str, Any]]:
    if not store.selector_registry.exists() and not store.selector_registry.is_symlink():
        return []
    data = _read_json(store.selector_registry)
    if set(data) != {"schema_version", "selectors"} or data.get("schema_version") != 1:
        raise _error("E_CACHE_CORRUPT", "selector registry schema is invalid")
    selectors = data.get("selectors")
    if not isinstance(selectors, list):
        raise _error("E_CACHE_CORRUPT", "selector registry list is invalid")
    result: List[Dict[str, Any]] = []
    seen: set = set()
    for item in selectors:
        if not isinstance(item, dict):
            raise _error("E_CACHE_CORRUPT", "selector registry entry is invalid")
        path = _registry_selector_path(store, item)
        key = str(path.resolve(strict=False))
        if key in seen:
            raise _error("E_CACHE_CORRUPT", "selector registry contains duplicate paths")
        seen.add(key)
        result.append({"path": key, "scope": item["scope"], "archive_sha256": item["archive_sha256"]})
    return result


def _write_selector_registry(store: RuntimeStore, selectors: Sequence[Mapping[str, Any]]) -> None:
    _atomic_write(store.selector_registry, _json_bytes({"schema_version": 1, "selectors": list(selectors)}))


def register_selector(store: RuntimeStore, selector: Path, scope: str, identity: Mapping[str, Any]) -> None:
    identity = validate_identity(identity)
    if scope not in SCOPES:
        raise _error("E_USAGE", "unsupported selector scope")
    entry = {
        "path": str(selector.resolve(strict=False)),
        "scope": scope,
        "archive_sha256": identity["archive_sha256"],
    }
    selectors = _read_selector_registry(store)
    key = entry["path"]
    selectors = [item for item in selectors if str(Path(item["path"]).resolve(strict=False)) != key]
    selectors.append(entry)
    _write_selector_registry(store, selectors)


def unregister_selector(store: RuntimeStore, selector: Path) -> None:
    if not store.selector_registry.exists() and not store.selector_registry.is_symlink():
        return
    key = str(selector.resolve(strict=False))
    selectors = _read_selector_registry(store)
    remaining = [item for item in selectors if str(Path(item["path"]).resolve(strict=False)) != key]
    if remaining != selectors:
        _write_selector_registry(store, remaining)


def _referenced_runtime_digests(store: RuntimeStore) -> set:
    """收集 selector 引用，不要求被引用的 cache 目前已健康。"""
    references: set = set()
    known_paths: set = set()
    for item in _read_selector_registry(store):
        path = Path(item["path"])
        if not path.exists() and not path.is_symlink():
            continue
        _safe_path(path)
        data = _load_selector(store, path, item["scope"])
        digest = data["identity"]["archive_sha256"]
        if digest != item["archive_sha256"]:
            raise _error("E_CACHE_CORRUPT", "selector registry does not match selector")
        references.add(digest)
        known_paths.add(str(path.resolve(strict=False)))

    current = Path.cwd().resolve(strict=True)
    root = _find_root(current, store)
    for scope in ("local", "project", "user"):
        path = store.selector_path(scope, root)
        if not path.exists() and not path.is_symlink():
            continue
        _safe_path(path)
        key = str(path.resolve(strict=False))
        if key in known_paths:
            continue
        data = _load_selector(store, path, scope)
        references.add(data["identity"]["archive_sha256"])
    return references


def _find_root(cwd: Path, store: RuntimeStore) -> Path:
    current = cwd
    fallback: Optional[Path] = None
    for _ in range(64):
        codex = current / ".codex"
        if codex.is_symlink():
            raise _error("E_SCOPE_UNSAFE", "project .codex directory is a symlink")
        guard = codex / "guardrail"
        for name in ("runtime.local.json", "runtime.json"):
            candidate = guard / name
            if candidate.exists() or candidate.is_symlink():
                _safe_path(candidate)
                return current
        if fallback is None and ((current / ".git").exists() or (codex.is_dir() and not codex.is_symlink())):
            fallback = current
        if current.parent == current:
            break
        current = current.parent
    return fallback or cwd


def resolve_runtime(event: Mapping[str, Any], store: RuntimeStore) -> Tuple[Optional[Dict[str, Any]], Optional[Path], Path]:
    cwd_value = event.get("cwd")
    if not isinstance(cwd_value, str) or not cwd_value:
        raise _error("E_RUNTIME_MISSING", "hook event cwd is invalid")
    cwd = Path(cwd_value).resolve(strict=True)
    if not cwd.is_dir():
        raise _error("E_RUNTIME_MISSING", "hook event cwd is not a directory")
    root = _find_root(cwd, store)
    for scope in ("local", "project", "user"):
        path = store.selector_path(scope, root)
        if path.exists() or path.is_symlink():
            identity, payload = _selector_identity(store, path, scope)
            return identity, payload, root
    return None, None, root


def _failure_output(event_name: str, code: str) -> bytes:
    if event_name == "SessionStart":
        return _json_bytes({"hookSpecificOutput": {"hookEventName": event_name, "additionalContext": "AI Guardrail unavailable (" + code + ")"}})
    return _json_bytes({"hookSpecificOutput": {"hookEventName": event_name, "permissionDecision": "deny", "permissionDecisionReason": "AI Guardrail unavailable (" + code + ")"}})


def _hook_environment(store: RuntimeStore, identity: Mapping[str, Any]) -> Dict[str, str]:
    """只傳遞 runtime 必要環境；selector/development 變數留在 loader 內。"""
    environment: Dict[str, str] = {}
    for key in ("PATH", "SystemRoot", "TEMP", "TMP", "TMPDIR"):
        value = os.environ.get(key)
        if isinstance(value, str):
            environment[key] = value
    home = str(store.root.parent.parent)
    environment["HOME"] = home
    if os.name == "nt":
        environment["USERPROFILE"] = home
    environment.update({
        "PYTHONUTF8": "1",
        "PYTHONIOENCODING": "utf-8",
        "AI_GUARDRAIL_MODE": str(identity["mode"]),
        "AI_GUARDRAIL_RUNTIME_VERSION": str(identity["runtime_version"]),
    })
    return environment


def dispatch(event_bytes: bytes, store: RuntimeStore, process: Optional[HookProcess] = None) -> int:
    if len(event_bytes) > MAX_EVENT_BYTES:
        sys.stdout.buffer.write(_failure_output("PreToolUse", "E_HOOK_FAILED"))
        return 0
    try:
        event = json.loads(event_bytes.decode("utf-8"))
        if not isinstance(event, dict):
            raise _error("E_HOOK_FAILED", "event is not an object")
        identity, payload, _ = resolve_runtime(event, store)
        if identity is None:
            return 0
        event_name = event.get("hook_event_name")
        slot = os.environ.get("AI_GUARDRAIL_LOADER_SLOT", "")
        if not isinstance(event_name, str):
            raise _error("E_HOOK_FAILED", "event name is invalid")
        if not slot:
            slot = "prompt.pii" if event_name == "UserPromptSubmit" else ("session.start" if event_name == "SessionStart" else "")
        entry = identity["entrypoints"].get(slot)
        if not entry:
            return 0
        entrypoint = payload.joinpath(*PurePosixPath(_validate_relative(entry)).parts)
        if not entrypoint.is_file() or entrypoint.is_symlink():
            raise _error("E_RUNTIME_MISSING", "verified entrypoint is unavailable")
        environment = _hook_environment(store, identity)
        result = (process or SubprocessHookProcess()).run(sys.executable, entrypoint, event_bytes, environment)
        if result[1]:
            sys.stdout.buffer.write(result[1])
        if result[0] != 0:
            raise _error("E_HOOK_FAILED", "runtime hook returned failure")
        return 0
    except ManagerError as error:
        sys.stdout.buffer.write(_failure_output(str(event.get("hook_event_name", "PreToolUse")) if "event" in locals() and isinstance(event, dict) else "PreToolUse", error.code))
        return 0
    except (OSError, ValueError, json.JSONDecodeError):
        sys.stdout.buffer.write(_failure_output("PreToolUse", "E_HOOK_FAILED"))
        return 0


def prepare_selection(args: argparse.Namespace) -> Dict[str, Any]:
    project = Path(args.project).resolve(strict=True)
    store = RuntimeStore(codex_home())
    selector = store.selector_path(args.scope, project)
    if selector.is_symlink():
        raise _error("E_SCOPE_UNSAFE", "selector is a symlink")
    migrations = prepare_legacy_migrations(store, project, args.scope)
    if migrations and not loader_is_installed(store):
        raise _error("E_RUNTIME_MISSING", "install the loader before migrating legacy hooks")
    existing_identity: Optional[Dict[str, Any]] = None
    if selector.exists():
        existing_identity, _ = _selector_identity(store, selector, args.scope)
    if selector.exists() and not args.update and not args.ref and not args.source:
        if existing_identity is not None and existing_identity["mode"] == args.mode:
            return {"identity": existing_identity, "selector": selector, "cache_hit": True,
                    "migrations": migrations, "owner": getattr(args, "owner", None)}
    source_name = args.source or (
        "local" if existing_identity is not None and existing_identity["source"] in ("development", "local", "test") else "github"
    )
    requested_ref = _validate_ref(args.ref or (
        existing_identity["ref"] if existing_identity is not None and not args.update else "main"
    ))
    if args.offline:
        index = _read_json(store.index)
        if index.get("schema_version") != 1 or not isinstance(index.get("entries"), list):
            raise _error("E_CACHE_CORRUPT", "offline runtime index is invalid")
        wanted = []
        for item in index["entries"]:
            if not isinstance(item, dict) or item.get("mode") != args.mode:
                continue
            if item.get("ref") != requested_ref:
                continue
            wanted.append(validate_identity(item))
        if len(wanted) != 1:
            raise _error("E_RUNTIME_MISSING", "offline ref is not uniquely indexed")
        identity = wanted[0]
        store.verify_cache(identity)
        return {"identity": identity, "selector": selector, "cache_hit": True,
                "migrations": migrations, "owner": getattr(args, "owner", None)}
    source = select_source(source_name)
    manifest = validate_manifest(source.fetch_manifest(requested_ref), expected_ref=requested_ref)
    identity = identity_from_manifest(manifest, args.mode, "development" if source.development else source_name)
    archive = source.fetch_archive(identity["archive_url"])
    validate_archive(archive, identity["archive_sha256"], identity["archive_size"])
    _, cache_hit = store.install(identity, archive)
    return {"identity": identity, "selector": selector, "cache_hit": cache_hit,
            "migrations": migrations, "owner": getattr(args, "owner", None)}


def commit_selection(prepared: Mapping[str, Any], scope: str, store: RuntimeStore) -> None:
    selector = Path(prepared["selector"])
    identity = dict(prepared["identity"])
    data = {"schema_version": 1, "scope": scope, "mode": identity["mode"], "identity": identity}
    if prepared.get("owner") is not None:
        data["owner"] = prepared["owner"]
    old = selector.read_bytes() if selector.exists() else None
    old_registry = snapshot_managed_file(store.selector_registry)
    try:
        _atomic_write(selector, _json_bytes(data), selector.stat().st_mode & 0o777 if selector.exists() else None)
        register_selector(store, selector, scope, identity)
    except BaseException as exc:
        try:
            if old is None:
                _remove_managed_file(selector)
            else:
                _atomic_write(selector, old)
            if old_registry is None:
                _remove_managed_file(store.selector_registry)
            else:
                _atomic_write(store.selector_registry, old_registry)
        except BaseException as rollback:
            raise _error("E_ROLLBACK_FAILED", "selector and rollback both failed") from rollback
        raise _error("E_SCOPE_UNSAFE", "selector transaction failed") from exc


def update_index(store: RuntimeStore, identity: Mapping[str, Any]) -> None:
    identity = validate_identity(identity)
    try:
        data = _read_json(store.index) if store.index.exists() else {"schema_version": 1, "entries": []}
    except ManagerError as error:
        if error.code == "E_RUNTIME_MISSING":
            data = {"schema_version": 1, "entries": []}
        else:
            raise
    if data.get("schema_version") != 1 or not isinstance(data.get("entries"), list):
        raise _error("E_CACHE_CORRUPT", "runtime index is invalid")
    entries = [x for x in data.get("entries", []) if not (isinstance(x, dict) and x.get("mode") == identity.get("mode") and x.get("ref") == identity.get("ref"))]
    entries.append(dict(identity))
    _atomic_write(store.index, _json_bytes({"schema_version": 1, "entries": entries}))


def _remove_managed_file(path: Path) -> None:
    if not path.exists() and not path.is_symlink():
        return
    _safe_path(path)
    if path.is_dir() and not path.is_symlink():
        raise _error("E_SCOPE_UNSAFE", "managed path is a directory")
    path.unlink()


def apply_legacy_migrations(migrations: Sequence[Mapping[str, Any]]) -> None:
    for migration in migrations:
        path = Path(migration["path"])
        old = migration["old"]
        if not isinstance(old, bytes) or not isinstance(migration.get("new"), bytes):
            raise _error("E_LEGACY_AMBIGUOUS", "legacy migration snapshot is invalid")
        mode = path.stat().st_mode & 0o777 if path.exists() else None
        _atomic_write(path, migration["new"], mode)


def restore_migration_snapshots(migrations: Sequence[Mapping[str, Any]]) -> None:
    for migration in reversed(list(migrations)):
        path = Path(migration["path"])
        old = migration.get("old")
        if old is None:
            _remove_managed_file(path)
        else:
            _atomic_write(path, old, path.stat().st_mode & 0o777 if path.exists() else None)


def snapshot_managed_file(path: Path) -> Optional[bytes]:
    if not path.exists() and not path.is_symlink():
        return None
    return _read_regular_bytes(path)


def ensure_personal_policy(store: RuntimeStore, identity: Mapping[str, Any], payload: Path) -> bool:
    if identity.get("mode") != "integrated-harness":
        return False
    policy = store.root / "orchestration-policy.md"
    if policy.exists() or policy.is_symlink():
        if policy.is_symlink():
            raise _error("E_SCOPE_UNSAFE", "personal policy is a symlink")
        _safe_path(policy)
        if not policy.is_file():
            raise _error("E_SCOPE_UNSAFE", "personal policy is not a regular file")
        return False
    bundled = payload / "orchestration-policy.md"
    if not bundled.is_file() or bundled.is_symlink():
        raise _error("E_RUNTIME_MISSING", "verified runtime does not contain policy")
    _atomic_write(policy, bundled.read_bytes())
    return True


def clean_legacy_global_hooks() -> None:
    path = codex_home() / "hooks.json"
    if not path.exists() and not path.is_symlink():
        return
    if path.is_symlink():
        raise _error("E_SCOPE_UNSAFE", "user hooks are a symlink")
    data = _read_json(path)
    hooks = data.get("hooks", {})
    if not isinstance(hooks, dict):
        raise _error("E_SCOPE_UNSAFE", "user hooks must contain an object")
    _legacy_mode_from_hooks(hooks, ("AI_GUARDRAIL_GLOBAL_DEFAULT=1 ",))
    for event, rules in hooks.items():
        if not isinstance(rules, list):
            raise _error("E_SCOPE_UNSAFE", "user hooks event must contain an array")
        for rule in rules:
            if not isinstance(rule, dict) or not isinstance(rule.get("hooks", []), list):
                raise _error("E_SCOPE_UNSAFE", "user hooks rule is invalid")
            rule["hooks"] = [entry for entry in rule["hooks"]
                             if not (isinstance(entry, dict) and isinstance(entry.get("command"), str)
                                     and entry["command"].startswith("AI_GUARDRAIL_GLOBAL_DEFAULT=1 "))]
    _atomic_write(path, _json_bytes(data), path.stat().st_mode & 0o777)


def remove_selection(args: argparse.Namespace) -> None:
    project = Path(args.project).resolve(strict=True)
    store = RuntimeStore(codex_home())
    path = store.selector_path(args.scope, project)
    if not path.exists() and not path.is_symlink():
        unregister_selector(store, path)
        return
    _safe_path(path)
    if path.is_dir():
        raise _error("E_SCOPE_UNSAFE", "selector is a directory")
    if getattr(args, "owner", None) is not None:
        data = _load_selector(store, path, args.scope)
        if data.get("owner") != args.owner:
            raise _error("E_SCOPE_UNSAFE", "selector is owned by another workflow")
    old_selector = _read_regular_bytes(path)
    old_registry = snapshot_managed_file(store.selector_registry)
    try:
        path.unlink()
        unregister_selector(store, path)
    except BaseException as exc:
        try:
            _atomic_write(path, old_selector)
            if old_registry is None:
                _remove_managed_file(store.selector_registry)
            else:
                _atomic_write(store.selector_registry, old_registry)
        except BaseException as rollback:
            raise _error("E_ROLLBACK_FAILED", "selector removal rollback failed") from rollback
        raise _error("E_SCOPE_UNSAFE", "selector removal transaction failed") from exc


def _verified_cache_candidate(store: RuntimeStore, candidate: Path) -> Optional[Dict[str, Any]]:
    try:
        metadata = _read_json(candidate / "runtime.json")
        identity = metadata.get("identity")
        if (metadata.get("complete") is not True or not isinstance(identity, dict)
                or identity.get("archive_sha256") != candidate.name):
            return None
        identity = validate_identity(identity)
        store.verify_cache(identity)
        return identity
    except ManagerError as error:
        if error.code in ("E_CACHE_CORRUPT", "E_RUNTIME_MISSING"):
            return None
        raise
    except (OSError, ValueError, UnicodeError):
        return None


def prune_cache(store: RuntimeStore, max_age_days: float, dry_run: bool) -> List[str]:
    if max_age_days < 0:
        raise _error("E_USAGE", "max age must not be negative")
    if not store.cache.exists():
        return []
    _safe_path(store.cache)
    if store.cache.is_symlink() or not store.cache.is_dir():
        raise _error("E_SCOPE_UNSAFE", "runtime cache is not a real directory")
    references = _referenced_runtime_digests(store)
    cutoff = time.time() - (max_age_days * 86400)
    candidates: List[Tuple[str, Path]] = []
    for candidate in store.cache.iterdir():
        if candidate.is_symlink() or not candidate.is_dir() or not SHA256_RE.fullmatch(candidate.name):
            continue
        lock = store.cache / (candidate.name + ".lock")
        if lock.exists() or lock.is_symlink():
            continue
        try:
            if candidate.stat().st_mtime >= cutoff:
                continue
        except OSError:
            continue
        if candidate.name in references or _verified_cache_candidate(store, candidate) is None:
            continue
        candidates.append((candidate.name, candidate))
    if dry_run:
        return [digest for digest, _ in candidates]

    removed: List[str] = []
    for digest, candidate in candidates:
        lock = store.cache / (digest + ".lock")
        try:
            fd = os.open(str(lock), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.close(fd)
        except FileExistsError:
            continue
        quarantined = candidate.with_name(candidate.name + ".prune-" + uuid.uuid4().hex[:8])
        try:
            if digest in _referenced_runtime_digests(store) or _verified_cache_candidate(store, candidate) is None:
                continue
            os.replace(str(candidate), str(quarantined))
            try:
                shutil.rmtree(quarantined)
            except OSError as error:
                if not candidate.exists() and quarantined.exists():
                    os.replace(str(quarantined), str(candidate))
                raise _error("E_SCOPE_UNSAFE", "runtime cache cleanup failed") from error
            removed.append(digest)
        finally:
            try:
                lock.unlink()
            except OSError:
                pass
    return removed


def verify_selection(args: argparse.Namespace) -> None:
    project = Path(args.project).resolve(strict=True)
    store = RuntimeStore(codex_home())
    path = store.selector_path(args.scope, project)
    if args.no_managed_mode:
        if path.exists() or path.is_symlink():
            raise _error("E_CACHE_CORRUPT", "managed selector still exists")
        return
    identity, _ = _selector_identity(store, path, args.scope)
    if args.expected and identity["mode"] != args.expected:
        raise _error("E_CACHE_CORRUPT", "selector mode does not match expectation")


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="codex-runtime-manager")
    sub = p.add_subparsers(dest="command", required=True)
    select = sub.add_parser("select")
    select.add_argument("mode", choices=MODES)
    select.add_argument("--scope", choices=SCOPES, default="project")
    select.add_argument("--project", default=".")
    select.add_argument("--ref")
    select.add_argument("--source", choices=("github", "local", "test"))
    select.add_argument("--owner", choices=("global-integrated-harness",))
    select.add_argument("--offline", action="store_true")
    select.add_argument("--update", action="store_true")
    remove = sub.add_parser("remove")
    remove.add_argument("--scope", choices=SCOPES, default="project")
    remove.add_argument("--project", default=".")
    remove.add_argument("--owner", choices=("global-integrated-harness",))
    verify = sub.add_parser("verify")
    verify.add_argument("expected", nargs="?")
    verify.add_argument("--no-managed-mode", action="store_true")
    verify.add_argument("--scope", choices=SCOPES, default="project")
    verify.add_argument("--project", default=".")
    verify.add_argument("--offline", action="store_true")
    dispatch_parser = sub.add_parser("dispatch")
    dispatch_parser.add_argument("--codex-home")
    loader = sub.add_parser("install-loader")
    loader.add_argument("--repo")
    loader.add_argument("--plugin-root")
    loader.add_argument("--update", action="store_true")
    loader.add_argument("--remove", action="store_true")
    prune = sub.add_parser("prune")
    prune.add_argument("--codex-home")
    prune.add_argument("--max-age", type=float, default=30.0)
    prune_mode = prune.add_mutually_exclusive_group()
    prune_mode.add_argument("--dry-run", action="store_true")
    prune_mode.add_argument("--apply", action="store_true")
    sub.add_parser("clean-legacy")
    return p


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = parser().parse_args(argv)
    try:
        if args.command == "select":
            prepared = prepare_selection(args)
            store = RuntimeStore(codex_home())
            old_index = snapshot_managed_file(store.index)
            selector_path = Path(prepared["selector"])
            old_selector = snapshot_managed_file(selector_path)
            old_registry = snapshot_managed_file(store.selector_registry)
            policy_path = store.root / "orchestration-policy.md"
            old_policy = snapshot_managed_file(policy_path)
            try:
                update_index(store, prepared["identity"])
                commit_selection(prepared, args.scope, store)
                _, payload = _selector_identity(store, Path(prepared["selector"]), args.scope)
                ensure_personal_policy(store, prepared["identity"], payload)
                apply_legacy_migrations(prepared.get("migrations", []))
            except BaseException:
                rollback_error: Optional[BaseException] = None
                try:
                    if old_index is None:
                        _remove_managed_file(store.index)
                    else:
                        _atomic_write(store.index, old_index)
                except BaseException as rollback:
                    rollback_error = rollback
                try:
                    if old_selector is None:
                        _remove_managed_file(selector_path)
                    else:
                        _atomic_write(selector_path, old_selector)
                except BaseException as rollback:
                    rollback_error = rollback_error or rollback
                try:
                    if old_policy is None:
                        _remove_managed_file(policy_path)
                    else:
                        _atomic_write(policy_path, old_policy)
                except BaseException as rollback:
                    rollback_error = rollback_error or rollback
                try:
                    if old_registry is None:
                        _remove_managed_file(store.selector_registry)
                    else:
                        _atomic_write(store.selector_registry, old_registry)
                except BaseException as rollback:
                    rollback_error = rollback_error or rollback
                try:
                    restore_migration_snapshots(prepared.get("migrations", []))
                except BaseException as rollback:
                    rollback_error = rollback_error or rollback
                if rollback_error is not None:
                    raise _error("E_ROLLBACK_FAILED", "selector transaction rollback failed") from rollback_error
                raise
            identity = prepared["identity"]
            print("Selected Codex mode %s (%s), ref=%s, commit=%s, sha256=%s, cache_hit=%s" %
                  (identity["mode"], args.scope, identity["ref"], identity["commit"], identity["archive_sha256"][:12], prepared["cache_hit"]))
            return 0
        if args.command == "remove":
            remove_selection(args)
            print("Removed Codex selector (%s)" % args.scope)
            return 0
        if args.command == "verify":
            verify_selection(args)
            print("Verified Codex selector (%s)" % args.scope)
            return 0
        if args.command == "dispatch":
            if args.codex_home:
                os.environ["CODEX_HOME"] = args.codex_home
            return dispatch(sys.stdin.buffer.read(MAX_EVENT_BYTES + 1), RuntimeStore(codex_home()))
        if args.command == "install-loader":
            repo = Path(args.repo).resolve(strict=True) if args.repo else None
            plugin_root = Path(args.plugin_root).resolve(strict=True) if args.plugin_root else None
            install_loader(repo, plugin_root, update=args.update, remove=args.remove)
            print("Installed Codex guardrail loader" if not args.remove else "Removed Codex guardrail loader")
            return 0
        if args.command == "prune":
            if args.codex_home:
                os.environ["CODEX_HOME"] = args.codex_home
            removed = prune_cache(RuntimeStore(codex_home()), args.max_age, dry_run=not args.apply)
            action = "Would prune" if not args.apply else "Pruned"
            print("%s %d Codex runtime cache entr%s" % (action, len(removed), "y" if len(removed) == 1 else "ies"))
            for digest in removed:
                print("  " + digest)
            return 0
        if args.command == "clean-legacy":
            clean_legacy_global_hooks()
            return 0
    except ManagerError as error:
        print("%s: %s" % (error.code, error), file=sys.stderr)
        return 1
    except (OSError, ValueError) as error:
        print("E_SCOPE_UNSAFE: managed operation failed", file=sys.stderr)
        return 1
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
