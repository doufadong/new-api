# ============================================
# new-api 上游自动合并脚本 (PowerShell 版本)
# 策略：自动检测本地与上游的差异文件，全量备份+恢复
# 无需手动维护文件清单，任何新修改都会自动保留
# ============================================

$RepoDir = "D:\AIWORK\new-api-main"
$BackupDir = "$RepoDir\.custom-backup"
$LogFile = "$RepoDir\.merge-log.txt"

function Write-Log($Message) {
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$Timestamp] $Message" | Tee-Object -FilePath $LogFile -Append | Write-Host
}

function Show-Header() {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "   new-api 上游自动合并脚本" -ForegroundColor Cyan
    Write-Host "   (自动检测差异文件策略)" -ForegroundColor DarkCyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
}

function Show-Success($Message) {
    Write-Host "  $Message" -ForegroundColor Green
}

function Show-Error($Message) {
    Write-Host "  [错误] $Message" -ForegroundColor Red
}

function Show-Info($Message) {
    Write-Host "  $Message" -ForegroundColor Yellow
}

function Show-Step($Number, $Total, $Message) {
    Write-Host ""
    Write-Host "[$Number/$Total] $Message" -ForegroundColor Blue
}

# 主程序
Show-Header

# 检查仓库目录
if (-not (Test-Path $RepoDir)) {
    Show-Error "找不到仓库目录: $RepoDir"
    Show-Info "请确认路径是否正确"
    Read-Host "按任意键退出"
    exit 1
}

Set-Location $RepoDir

Write-Log "开始检查上游更新..."

# 步骤 1: 获取上游最新代码
Show-Step 1 6 "获取上游最新代码..."
try {
    git fetch upstream main 2>&1 | Out-Null
    Show-Success "获取完成"
} catch {
    Show-Error "获取上游代码失败！请检查网络或 SSH 配置。"
    Write-Log "获取上游失败: $_"
    Read-Host "按任意键退出"
    exit 1
}

# 步骤 2: 检查是否有新更新
Show-Step 2 6 "检查是否有新的上游更新..."

$NewCommits = (git rev-list --count HEAD..upstream/main) -as [int]

if ($NewCommits -eq 0) {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "   没有新的上游更新！" -ForegroundColor Green
    Write-Host "   当前已是最新代码。" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    Write-Log "没有新更新，退出"
    Read-Host "按任意键退出"
    exit 0
}

Show-Info "发现 $NewCommits 个新提交，准备合并！"
Write-Log "发现 $NewCommits 个新提交"

# 显示即将合并的提交
Write-Host ""
Show-Info "即将合并的提交:"
git log --oneline HEAD..upstream/main | ForEach-Object { Write-Host "    $_" }

# 步骤 3: 自动检测本地修改文件（核心改进）
Show-Step 3 6 "自动检测本地与上游的差异文件..."

# 获取所有与上游不同的文件（自动检测，无需手动维护清单）
$DiffFiles = git diff HEAD upstream/main --name-only

if ($DiffFiles.Count -eq 0) {
    Show-Info "没有本地修改文件，直接合并即可"
} else {
    Write-Host ""
    Show-Info "检测到以下本地修改文件 (与上游不同):"
    foreach ($File in $DiffFiles) {
        Write-Host "    $File" -ForegroundColor Magenta
    }
    Show-Info "共 $($DiffFiles.Count) 个文件将被备份保留"
}

Write-Log "检测到 $($DiffFiles.Count) 个差异文件"

# 步骤 4: 备份本地修改文件
Show-Step 4 6 "备份本地修改文件..."

# 清空旧备份目录（确保只保留本次的差异文件）
if (Test-Path $BackupDir) {
    Remove-Item -Path "$BackupDir\*" -Recurse -Force -ErrorAction SilentlyContinue
} else {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
}

# 记录差异文件清单（用于恢复时知道每个文件的原路径）
$ManifestFile = "$BackupDir\.manifest"
$DiffFiles | Out-File -FilePath $ManifestFile -Encoding UTF8

$BackupCount = 0
foreach ($File in $DiffFiles) {
    $SourcePath = Join-Path $RepoDir $File
    if (Test-Path $SourcePath) {
        # 保持目录结构（避免同名文件冲突）
        $DestPath = Join-Path $BackupDir $File
        $DestDir = Split-Path $DestPath -Parent
        if (-not (Test-Path $DestDir)) {
            New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
        }
        Copy-Item -Path $SourcePath -Destination $DestPath -Force
        $BackupCount++
    }
}

Show-Success "已备份 $BackupCount 个文件到: $BackupDir"
Show-Success "文件清单保存在: $ManifestFile"
Write-Log "备份了 $BackupCount 个文件"

# 步骤 5: 重置到上游最新代码
Show-Step 5 6 "重置到上游最新代码..."
try {
    git reset --hard upstream/main 2>&1 | Out-Null
    Show-Success "重置完成"
    Write-Log "重置到 upstream/main 成功"
} catch {
    Show-Error "重置失败！"
    Write-Log "重置失败: $_"
    Read-Host "按任意键退出"
    exit 1
}

# 步骤 6: 重新覆盖本地修改文件
Show-Step 6 6 "恢复本地修改文件..."

$RestoreCount = 0
foreach ($File in $DiffFiles) {
    $BackupPath = Join-Path $BackupDir $File
    $TargetPath = Join-Path $RepoDir $File
    if (Test-Path $BackupPath) {
        $TargetDir = Split-Path $TargetPath -Parent
        if (-not (Test-Path $TargetDir)) {
            New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
        }
        Copy-Item -Path $BackupPath -Destination $TargetPath -Force
        $RestoreCount++
        Write-Host "    已恢复: $File" -ForegroundColor DarkGreen
    }
}

Show-Success "已恢复 $RestoreCount 个修改文件"
Write-Log "恢复了 $RestoreCount 个文件"

# 提交并推送
Write-Host ""
Show-Info "正在提交合并..."
git add . 2>&1 | Out-Null
git commit -m "custom: merge upstream latest + keep local modifications (auto-detected $RestoreCount custom files)" 2>&1 | Out-Null
Show-Success "提交完成"

Show-Info "正在推送到 GitHub..."
try {
    git push origin main 2>&1 | Out-Null
    Show-Success "推送完成"
    Write-Log "推送成功"
} catch {
    Show-Error "推送失败！请检查 SSH 配置。"
    Write-Log "推送失败: $_"
    Read-Host "按任意键退出"
    exit 1
}

# 记录成功
Write-Log "合并成功，合并了 $NewCommits 个新提交，保留了 $RestoreCount 个本地修改"

# 显示成功信息
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "   合并完成！" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  合并了 $NewCommits 个上游新提交" -ForegroundColor White
Write-Host "  保留了 $RestoreCount 个本地修改文件" -ForegroundColor White
Write-Host "  已推送到 doufadong/new-api (测试仓库)" -ForegroundColor White
Write-Host ""
Write-Host "  保留的文件清单:" -ForegroundColor Cyan
foreach ($File in $DiffFiles) {
    Write-Host "    $File" -ForegroundColor Gray
}
Write-Host ""
Write-Host "  最新提交记录:" -ForegroundColor Cyan
git log --oneline -5 | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
Write-Host ""

Read-Host "按任意键退出"
