param([string]$GameDir = "", [switch]$NoGui)
$ErrorActionPreference = "Stop"
$PatchDir = $PSScriptRoot
try { Start-Transcript -Path (Join-Path $PatchDir "install_log.txt") -Append -Force | Out-Null } catch {}
function Msg($text, $icon) {
    if ($NoGui) { return }
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $ic = if ($icon -eq "Error") { [System.Windows.Forms.MessageBoxIcon]::Error } else { [System.Windows.Forms.MessageBoxIcon]::Information }
        [System.Windows.Forms.MessageBox]::Show($text, "LoneWolf 汉化 v2.3 卸载", [System.Windows.Forms.MessageBoxButtons]::OK, $ic) | Out-Null
    } catch {}
}
function Fail($m) { Write-Host ("[失败] " + $m) -ForegroundColor Red; Msg ("卸载失败：`r`n" + $m) "Error"; exit 1 }

$ORIG_RES = "91457bf6df3dbcf0716de6153658d2f2926da67dbb10559b64ed04180a7cb20b"
$SMALL = @(
    @{ n = "mainData";            rel = "mainData" },
    @{ n = "level0";              rel = "level0" },
    @{ n = "Assembly-CSharp.dll"; rel = "Managed\Assembly-CSharp.dll" }
)

# ---- locate game: 只认补丁包所在文件夹的上一级，不做任何扫描 ----
if (-not $GameDir) { $GameDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\lonewolf_Data")) }
$GameDir = $GameDir.Trim('"').Trim()
Write-Host ""
Write-Host "卸载目标" -ForegroundColor Cyan
Write-Host ("  " + $GameDir) -ForegroundColor Yellow
Write-Host "  （由补丁包位置推导：包所在文件夹的上一级 + lonewolf_Data）"
Write-Host ""
if (-not (Test-Path (Join-Path $GameDir "resources.assets"))) {
    Fail ("补丁包上一级目录里没有 lonewolf_Data。`r`n请把补丁包放回游戏根目录后再运行。`r`n推断目标: " + $GameDir)
}

if (Get-Process -Name "lonewolf*" -ErrorAction SilentlyContinue) { Fail "游戏正在运行，请先完全退出。" }

Add-Type -TypeDefinition @'
using System; using System.IO; using System.Security.Cryptography;
public static class LwHash {
    public static string Sha(string path) {
        using (var sha = SHA256.Create())
        using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 20)) {
            byte[] h = sha.ComputeHash(fs);
            var sb = new System.Text.StringBuilder();
            foreach (byte b in h) sb.Append(b.ToString("x2"));
            return sb.ToString();
        }
    }
}
'@

$res    = Join-Path $GameDir "resources.assets"
$bak    = Join-Path $GameDir "resources.assets.orig_bak"
$bakDir = Join-Path $GameDir "chinese_backup_v2_delta"

if (-not (Test-Path $bak)) {
    Write-Host "未找到 resources.assets.orig_bak。" -ForegroundColor Yellow
    Write-Host "说明：这份安装没有留下可还原的原文件备份。请用 Steam『验证文件完整性』还原成英文原版。"
    Msg "未找到备份文件。`r`n请用 Steam『验证文件完整性』还原。" "Error"
    exit 1
}

Write-Host "正在还原 resources.assets ..."
Remove-Item $res -Force -ErrorAction SilentlyContinue
Rename-Item -LiteralPath $bak -NewName "resources.assets"

$h = [LwHash]::Sha($res)
if ($h -eq $ORIG_RES) { Write-Host "[OK] resources.assets 已还原为英文原版" -ForegroundColor Green }
else { Write-Host ("[警告] resources.assets 哈希与原版基准不符：" + $h) -ForegroundColor Yellow }

foreach ($s in $SMALL) {
    $b = Join-Path $bakDir $s.n
    $d = Join-Path $GameDir $s.rel
    if (Test-Path $b) { Copy-Item $b $d -Force; Write-Host ("[OK] 已还原 " + $s.n) -ForegroundColor Green }
    else { Write-Host ("[跳过] 无备份: " + $s.n) -ForegroundColor Yellow }
}

Write-Host ""
Write-Host "卸载完成，游戏已回到英文原版。" -ForegroundColor Green
Msg "卸载完成，游戏已回到英文原版。" "Info"
exit 0
