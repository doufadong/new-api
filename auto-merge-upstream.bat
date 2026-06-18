@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: ============================================
:: new-api 上游自动合并脚本 (Bat 版本)
:: 策略：自动检测本地与上游的差异文件，全量备份+恢复
:: 无需手动维护文件清单，任何新修改都会自动保留
:: ============================================

:: 设置路径
set REPO_DIR=D:\AIWORK\new-api-main
set BACKUP_DIR=%REPO_DIR%\.custom-backup
set LOG_FILE=%REPO_DIR%\.merge-log.txt
set MANIFEST_FILE=%BACKUP_DIR%\.manifest

echo ============================================
echo   new-api 上游自动合并脚本
echo   (自动检测差异文件策略)
echo ============================================
echo.

:: 检查仓库目录是否存在
if not exist "%REPO_DIR%" (
    echo [错误] 找不到仓库目录: %REPO_DIR%
    echo 请确认路径是否正确。
    pause
    exit /b 1
)

cd /d "%REPO_DIR%"

:: 记录日志
echo [%date% %time%] 开始检查上游更新 >> "%LOG_FILE%"

:: 步骤 1: 获取上游最新代码
echo [1/6] 正在获取上游最新代码...
git fetch upstream main
if errorlevel 1 (
    echo [错误] 获取上游代码失败！请检查网络或 SSH 配置。
    pause
    exit /b 1
)
echo [1/6] 完成

:: 步骤 2: 检查是否有新更新
echo [2/6] 检查是否有新的上游更新...

for /f "delims=" %%a in ('git rev-list --count HEAD..upstream/main') do set NEW_COMMITS=%%a

if %NEW_COMMITS%==0 (
    echo.
    echo ============================================
    echo   没有新的上游更新！
    echo   当前已是最新代码。
    echo ============================================
    echo [%date% %time%] 没有新更新，退出 >> "%LOG_FILE%"
    pause
    exit /b 0
)

echo [2/6] 发现 %NEW_COMMITS% 个新提交，准备合并！

:: 显示即将合并的提交
echo.
echo 即将合并的提交:
git log --oneline HEAD..upstream/main

:: 步骤 3: 自动检测本地修改文件（核心改进）
echo.
echo [3/6] 自动检测本地与上游的差异文件...

:: 清空旧备份目录
if exist "%BACKUP_DIR%" (
    del /q "%BACKUP_DIR%\*" 2>nul
    for /d %%d in ("%BACKUP_DIR%\*") do rd /s /q "%%d" 2>nul
) else (
    mkdir "%BACKUP_DIR%"
)

:: 获取差异文件清单并保存到 manifest
git diff HEAD upstream/main --name-only > "%MANIFEST_FILE%"

:: 统计差异文件数量
set DIFF_COUNT=0
for /f "delims=" %%f in (%MANIFEST_FILE%) do (
    set /a DIFF_COUNT+=1
)

echo.
echo 检测到 %DIFF_COUNT% 个本地修改文件 (与上游不同):
for /f "delims=" %%f in (%MANIFEST_FILE%) do (
    echo     %%f
)
echo [%date% %time%] 检测到 %DIFF_COUNT% 个差异文件 >> "%LOG_FILE%"

:: 步骤 4: 备份本地修改文件（保持目录结构）
echo.
echo [4/6] 备份本地修改文件...

set BACKUP_COUNT=0
for /f "delims=" %%f in (%MANIFEST_FILE%) do (
    if exist "%%f" (
        :: 保持目录结构，避免同名文件冲突
        set "SRC=%%f"
        set "DEST=%BACKUP_DIR%\%%f"
        
        :: 创建目标目录
        for %%d in ("!DEST!") do (
            if not exist "%%~dpd" mkdir "%%~dpd"
        )
        
        copy /Y "!SRC!" "!DEST!" >nul
        set /a BACKUP_COUNT+=1
    )
)

echo [4/6] 已备份 %BACKUP_COUNT% 个文件到: %BACKUP_DIR%

:: 步骤 5: 重置到上游最新代码
echo.
echo [5/6] 重置到上游最新代码...
git reset --hard upstream/main
if errorlevel 1 (
    echo [错误] 重置失败！
    pause
    exit /b 1
)
echo [5/6] 重置完成

:: 步骤 6: 恢复本地修改文件
echo.
echo [6/6] 恢复本地修改文件...

set RESTORE_COUNT=0
for /f "delims=" %%f in (%MANIFEST_FILE%) do (
    set "BACKUP_SRC=%BACKUP_DIR%\%%f"
    set "TARGET=%%f"
    
    if exist "!BACKUP_SRC!" (
        :: 创建目标目录
        for %%d in ("!TARGET!") do (
            if not exist "%%~dpd" mkdir "%%~dpd"
        )
        
        copy /Y "!BACKUP_SRC!" "!TARGET!" >nul
        set /a RESTORE_COUNT+=1
        echo     已恢复: %%f
    )
)

echo [6/6] 已恢复 %RESTORE_COUNT% 个修改文件

:: 提交并推送
echo.
echo [提交] 正在提交合并...
git add .
git commit -m "custom: merge upstream latest + keep local modifications (auto-detected %RESTORE_COUNT% custom files)"

echo [推送] 正在推送到 GitHub...
git push origin main
if errorlevel 1 (
    echo [错误] 推送失败！请检查 SSH 配置。
    pause
    exit /b 1
)

:: 记录成功日志
echo [%date% %time%] 合并成功，合并了 %NEW_COMMITS% 个新提交，保留了 %RESTORE_COUNT% 个本地修改 >> "%LOG_FILE%"

:: 显示成功信息
echo.
echo ============================================
echo   合并完成！
echo ============================================
echo.
echo 合并了 %NEW_COMMITS% 个上游新提交
echo 保留了 %RESTORE_COUNT% 个本地修改文件
echo 已推送到 doufadong/new-api (测试仓库)
echo.

:: 显示保留的文件清单
echo 保留的文件清单:
for /f "delims=" %%f in (%MANIFEST_FILE%) do (
    echo     %%f
)
echo.

:: 显示最新的提交日志
echo 最新提交记录:
git log --oneline -5
echo.

pause
