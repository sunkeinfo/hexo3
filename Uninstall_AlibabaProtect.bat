@echo off
REM -------------------------------------------------------------------
REM 描述：此脚本用于强制停止并彻底删除阿里巴巴电脑安全服务 (Alibaba PC SAFE Service / AlibabaProtect)。
REM 重要：请务必右键单击此文件，并选择“以管理员身份运行”。
REM -------------------------------------------------------------------

:: 设置窗口标题
title AlibabaProtect 强制卸载工具

echo.
echo =======================================================
echo      正在开始强制卸载 Alibaba PC SAFE Service...
echo      请确保以管理员身份运行此脚本！
echo =======================================================
echo.
pause

:: 步骤 1: 强制停止相关进程
echo [步骤 1/4] 正在尝试停止 AlibabaProtect 相关进程...
taskkill /F /IM AlibabaProtect.exe /T >nul 2>&1
taskkill /F /IM AlibabaProtectUI.exe /T >nul 2>&1
echo 进程已停止 (如果存在)。
echo.

:: 步骤 2: 停止并删除 Windows 服务
echo [步骤 2/4] 正在停止并删除 AlibabaProtect 服务...
net stop AlibabaProtect >nul 2>&1
sc delete AlibabaProtect >nul 2>&1
echo 服务已删除 (如果存在)。
echo.

:: 步骤 3: 删除程序文件
echo [步骤 3/4] 正在删除程序文件...
set "AlibabaPath=%ProgramFiles(x86)%\AlibabaProtect"
if exist "%AlibabaPath%" (
    echo 正在获取文件夹所有权: %AlibabaPath%
    takeown /F "%AlibabaPath%" /R /D Y >nul 2>&1
    echo 正在授予管理员完全控制权限...
    icacls "%AlibabaPath%" /grant Administrators:F /T >nul 2>&1
    echo 正在删除文件夹...
    rmdir /S /Q "%AlibabaPath%"
    echo 文件夹已成功删除。
) else (
    echo 程序文件夹未找到，可能已被删除。
)
echo.

:: 步骤 4: 清理计划任务 (可选但建议)
echo [步骤 4/4] 正在清理相关的计划任务...
schtasks /delete /TN "AlibabaProtect" /F >nul 2>&1
echo 计划任务已清理 (如果存在)。
echo.

:: 完成
echo =======================================================
echo      所有操作已完成！
echo      AlibabaProtect 已从您的系统中移除。
echo      建议您现在重启计算机以确保所有更改生效。
echo =======================================================
echo.
pause
exit
