param([string]$GameDir = "", [switch]$NoGui, [switch]$Yes)
$ErrorActionPreference = "Stop"
$PatchDir = $PSScriptRoot
try { Start-Transcript -Path (Join-Path $PatchDir "install_log.txt") -Append -Force | Out-Null } catch {}
$logPath  = Join-Path $PatchDir "install_log.txt"
function Msg($text, $icon) {
    if ($NoGui) { return }
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $ic = if ($icon -eq "Error") { [System.Windows.Forms.MessageBoxIcon]::Error } else { [System.Windows.Forms.MessageBoxIcon]::Information }
        [System.Windows.Forms.MessageBox]::Show($text, "LoneWolf 汉化 v2.3 差分包", [System.Windows.Forms.MessageBoxButtons]::OK, $ic) | Out-Null
    } catch {}
}
function Fail($m) {
    Write-Host ""
    Write-Host ("[失败] " + $m) -ForegroundColor Red
    Write-Host ("日志: " + $logPath)
    Msg ("安装失败：`r`n" + $m + "`r`n`r`n日志：`r`n" + $logPath) "Error"
    exit 1
}

$ORIG_RES = "91457bf6df3dbcf0716de6153658d2f2926da67dbb10559b64ed04180a7cb20b"
$PAT_RES  = "a69d405b45210fb015d8849ac2b56936e02b38e5fe4b9fd2dc5fdb30f162f8d8"
$PAT_MD   = "a5b6ce6bf629a608a00de4ed5bcffa9c791409a30ef08941ef3462b2ff570864"
$PAT_L0   = "73e110aaa3d73dcacdc33dc371a6049ec00bcfbe58ee11332dc8bacd4bc6611f"
$PAT_DLL  = "1f6864b20d662454c3cdf7c298ff1e4f469ebfe8f121831d147c4ae62cd3c010"
$DELTA_NAME = "resources.assets.lwd"
$SMALL = @(
    @{ n = "mainData";             rel = "mainData";                     sha = $PAT_MD },
    @{ n = "level0";               rel = "level0";                       sha = $PAT_L0 },
    @{ n = "Assembly-CSharp.dll";  rel = "Managed\Assembly-CSharp.dll";  sha = $PAT_DLL }
)

Write-Host "== LoneWolf 汉化 v2.3 · 差分包安装 ==" -ForegroundColor Cyan

# ---- locate game: 只认补丁包所在文件夹的上一级，不做任何扫描 ----
$explicitDir = [bool]$GameDir
if (-not $GameDir) { $GameDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\lonewolf_Data")) }
$GameDir = $GameDir.Trim('"').Trim()
Write-Host ""
Write-Host "安装目标" -ForegroundColor Cyan
Write-Host ("  " + $GameDir) -ForegroundColor Yellow
if (-not $explicitDir) { Write-Host "  （由补丁包位置推导：包所在文件夹的上一级 + lonewolf_Data）" }
Write-Host ""
if (-not (Test-Path (Join-Path $GameDir "resources.assets"))) {
    Fail ("补丁包上一级目录里没有 lonewolf_Data。`r`n`r`n补丁包目录: " + $PSScriptRoot + "`r`n推断目标: " + $GameDir + "`r`n`r`n请把整个补丁包文件夹放进游戏根目录（与 lonewolf.exe 同级）后再运行。")
}

# ---- 版本信息（尽力而为，仅提示，不参与判定）----
$buildid = $null
$acf = $null
try {
    $gameRoot  = Split-Path $GameDir -Parent
    $steamapps = Split-Path (Split-Path $gameRoot -Parent) -Parent
    if ($steamapps) { $acf = Join-Path $steamapps "appmanifest_279440.acf" }
} catch { $acf = $null }
if ($acf -and (Test-Path $acf)) {
    try { $buildid = [regex]::Match((Get-Content $acf -Raw -Encoding UTF8), '"buildid"\s+"(\d+)"').Groups[1].Value } catch {}
}
if ($buildid) {
    Write-Host ("游戏构建: Steam AppID 279440 · buildid " + $buildid)
    if ($buildid -ne "510115") {
        Write-Host "  注意：本补丁基于 buildid 510115（2022-04-02）制作；你的构建不同，若哈希校验不通过会拒绝安装。" -ForegroundColor Yellow
    }
} else {
    Write-Host "游戏构建: 未找到 appmanifest_279440.acf（非 Steam 安装或非默认库），以下按文件哈希校验"
}
# ---- process check ----
if (Get-Process -Name "lonewolf*" -ErrorAction SilentlyContinue) { Fail "游戏正在运行，请先完全退出游戏。" }

# ---- package check ----
$deltaPath = Join-Path $PatchDir $DELTA_NAME
if (-not (Test-Path $deltaPath)) { Fail ("补丁包缺少 " + $DELTA_NAME) }
foreach ($s in $SMALL) { if (-not (Test-Path (Join-Path $PatchDir ("files\" + $s.n)))) { Fail ("补丁包缺少 files\" + $s.n) } }

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.IO.Compression;
using System.Security.Cryptography;

public static class LwApply {
    public static string Sha256(string path) {
        using (var sha = SHA256.Create())
        using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 20)) {
            byte[] h = sha.ComputeHash(fs);
            var sb = new System.Text.StringBuilder();
            foreach (byte b in h) sb.Append(b.ToString("x2"));
            return sb.ToString();
        }
    }
    public static long Apply(string srcPath, string deltaPath, string outPath) {
        using (var inFs = new FileStream(deltaPath, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 20))
        using (var gz = new GZipStream(inFs, CompressionMode.Decompress))
        using (var br = new BinaryReader(gz))
        using (var src = new FileStream(srcPath, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 20))
        using (var o = new FileStream(outPath, FileMode.Create, FileAccess.Write, FileShare.None, 1 << 20)) {
            var magic = br.ReadBytes(4);
            if (magic.Length != 4 || magic[0] != 0x4C || magic[1] != 0x57 || magic[2] != 0x44 || magic[3] != 0x31) throw new Exception("delta magic mismatch");
            long srcSize = br.ReadInt64();
            long patSize = br.ReadInt64();
            if (srcSize != src.Length) throw new Exception("source size mismatch");
            o.SetLength(patSize);
            long nextMark = patSize / 10; int shown = 0;
            var buf = new byte[1 << 20];
            while (true) {
                int op;
                try { op = br.ReadByte(); } catch (EndOfStreamException) { break; }
                if (op == 1) {
                    long off = br.ReadInt64();
                    int lenC = br.ReadInt32();
                    src.Position = off;
                    int remain = lenC;
                    while (remain > 0) {
                        int r = src.Read(buf, 0, Math.Min(buf.Length, remain));
                        if (r <= 0) throw new Exception("source EOF");
                        o.Write(buf, 0, r); remain -= r;
                    }
                } else if (op == 2) {
                    int lenL = br.ReadInt32();
                    int remain = lenL;
                    while (remain > 0) {
                        int r = br.Read(buf, 0, Math.Min(buf.Length, remain));
                        if (r <= 0) throw new Exception("delta EOF");
                        o.Write(buf, 0, r); remain -= r;
                    }
                } else throw new Exception("bad op " + op);
                if (o.Position >= nextMark && shown < 10) {
                    shown++;
                    Console.WriteLine("    重建进度 " + (shown * 10) + "%  (" + (o.Position >> 20) + " MB / " + (patSize >> 20) + " MB)");
                    nextMark += patSize / 10;
                }
            }
            if (o.Length != patSize) throw new Exception("output size mismatch");
            return o.Length;
        }
    }
}
'@

$resPath  = Join-Path $GameDir "resources.assets"
$newPath  = Join-Path $GameDir "resources.assets.new"
$bakPath  = Join-Path $GameDir "resources.assets.orig_bak"
$bakDir   = Join-Path $GameDir "chinese_backup_v2_delta"

$h = [LwApply]::Sha256($resPath)
Write-Host ("当前 resources.assets: " + $h.Substring(0,16) + "...")
if ($h -eq $PAT_RES) {
    Write-Host "已经是 v2.3 汉化版，无需重复安装。" -ForegroundColor Green
    Msg "已经是 v2.3 汉化版，无需重复安装。" "Info"
    exit 0
}
if ($h -ne $ORIG_RES) {
    Fail ("resources.assets 与原版基准不一致（可能游戏已更新或被其他补丁改过）。`r`n当前: " + $h)
}
Write-Host "校验通过：这是英文原版" -ForegroundColor Green

# ---- backup small files (first run) ----
if (-not (Test-Path $bakDir)) {
    New-Item -ItemType Directory -Force $bakDir | Out-Null
    foreach ($s in $SMALL) {
        $src = Join-Path $GameDir $s.rel
        if (Test-Path $src) {
            $dst = Join-Path $bakDir $s.n
            Copy-Item $src $dst -Force
        }
    }
    Write-Host ("[备份] 原文件已备份到 " + $bakDir) -ForegroundColor Green
}

# ---- rebuild (to temp file, never in place) ----
Write-Host "开始重建 resources.assets（约需 10-30 秒，请勿关闭窗口）..." -ForegroundColor Cyan
$sw = [Diagnostics.Stopwatch]::StartNew()
try {
    $size = [LwApply]::Apply($resPath, $deltaPath, $newPath)
} catch {
    if (Test-Path $newPath) { Remove-Item $newPath -Force -ErrorAction SilentlyContinue }
    Fail ("重建失败：" + $_.Exception.Message)
}
Write-Host ("重建完成：" + ("{0:N0}" -f $size) + " B，用时 " + [math]::Round($sw.Elapsed.TotalSeconds,1) + " 秒")

# ---- verify rebuilt ----
$h2 = [LwApply]::Sha256($newPath)
if ($h2 -ne $PAT_RES) {
    Remove-Item $newPath -Force -ErrorAction SilentlyContinue
    Fail ("重建结果哈希不符：`r`n" + $h2 + "`r`n原文件未被改动。")
}
Write-Host "重建结果校验通过" -ForegroundColor Green

# ---- atomic swap ----
try {
    if (Test-Path $bakPath) { Remove-Item $bakPath -Force }
    Rename-Item -LiteralPath $resPath -NewName "resources.assets.orig_bak"
    Rename-Item -LiteralPath $newPath -NewName "resources.assets"
} catch {
    if ((Test-Path $bakPath) -and -not (Test-Path $resPath)) { Rename-Item -LiteralPath $bakPath -NewName "resources.assets" }
    Fail ("替换失败：" + $_.Exception.Message)
}

# ---- small files ----
$failed = $false
foreach ($s in $SMALL) {
    $src = Join-Path $PatchDir ("files\" + $s.n)
    $dst = Join-Path $GameDir $s.rel
    try {
        Copy-Item $src $dst -Force
        $hh = [LwApply]::Sha256($dst)
        if ($hh -ne $s.sha) { Write-Host ("[校验失败] " + $s.n) -ForegroundColor Red; $failed = $true }
        else { Write-Host ("[OK] " + $s.n) -ForegroundColor Green }
    } catch { Write-Host ("[写入失败] " + $s.n + " : " + $_.Exception.Message) -ForegroundColor Red; $failed = $true }
}

if ($failed) {
    Write-Host "部分文件失败，正在回滚..." -ForegroundColor Yellow
    if (Test-Path $bakPath) { Remove-Item $resPath -Force -ErrorAction SilentlyContinue; Rename-Item -LiteralPath $bakPath -NewName "resources.assets" }
    foreach ($s in $SMALL) {
        $b = Join-Path $bakDir $s.n
        if (Test-Path $b) { Copy-Item $b (Join-Path $GameDir $s.rel) -Force }
    }
    Fail "安装未完成，已回滚到原版状态。"
}

# ---- final verify ----
$allOk = $true
if ([LwApply]::Sha256((Join-Path $GameDir "resources.assets")) -ne $PAT_RES) { $allOk = $false }
foreach ($s in $SMALL) { if ([LwApply]::Sha256((Join-Path $GameDir $s.rel)) -ne $s.sha) { $allOk = $false } }
if (-not $allOk) { Fail "最终校验未通过，请运行卸载脚本还原后重试。" }

Write-Host ""
Write-Host "安装完成！（v2.3 差分包）" -ForegroundColor Green
Write-Host "  · 从 Steam 启动游戏（不要直接双击 exe）"
Write-Host "  · 语言：设置 → Language → 【中文】"
Write-Host "  · 卸载：双击 卸载汉化.bat（会用到 resources.assets.orig_bak）"
Write-Host ("  · 备份目录: " + $bakDir)
Msg "安装完成！`r`n`r`n从 Steam 启动游戏，设置 → Language → 中文。" "Info"
exit 0
