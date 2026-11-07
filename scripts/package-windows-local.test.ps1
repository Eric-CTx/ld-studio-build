$ErrorActionPreference = "Stop"
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ("lingdong-package-test-" + [guid]::NewGuid())
$payload = Join-Path $fixtureRoot "payload"
$installer = Join-Path $fixtureRoot "fixture.exe"
$scriptPath = Join-Path $PSScriptRoot "package-windows-local.ps1"

function 7z {
	param($Operation, $Archive, $Output, [switch]$y)
	if ($Operation -ne "x" -or $Archive -ne $installer -or -not $y) { throw "提取器参数不符" }
	Copy-Item -Path "$payload/*" -Destination $Output.Substring(2) -Recurse
	$global:LASTEXITCODE = 0
}

try {
	$files = @(
		"Cap.exe", "cap-muxer.exe", "cap-cli.exe",
		"avcodec-61.dll", "avdevice-61.dll", "avfilter-10.dll", "avformat-61.dll",
		"avutil-59.dll", "postproc-58.dll", "swresample-5.dll", "swscale-8.dll",
		"dxcompiler.dll", "dxil.dll", "onnxruntime.dll", "onnxruntime_providers_shared.dll",
		"licenses/dxc/LICENSE-MS.txt", "assets/music/demo.mp3",
		"assets/backgrounds/macOS/a.jpg", "assets/backgrounds/blue/a.jpg",
		"assets/backgrounds/cities/a.jpg", "assets/backgrounds/dark/a.jpg",
		"assets/backgrounds/orange/a.jpg", "assets/backgrounds/purple/a.jpg"
	)
	foreach ($file in $files + @('cap-exporter.exe', 'cap-gpui.exe', 'assets/rive/legacy.riv', '$PLUGINSDIR/plugin.dll')) {
		$path = Join-Path $payload $file
		$null = New-Item -ItemType Directory -Path (Split-Path $path) -Force
		Set-Content -LiteralPath $path -Value "测试载荷 $file"
	}
	Set-Content -LiteralPath $installer -Value "模拟 NSIS 提取边界"
	$output = Join-Path $fixtureRoot "delivery"
	& $scriptPath -InstallerPath $installer -OutputDirectory $output
	$manifest = Get-Content -LiteralPath (Join-Path $output "构建校验.json") -Raw | ConvertFrom-Json
	if (@(Compare-Object ($files | Sort-Object) ($manifest.files.path | Sort-Object)).Count) { throw "交付文件清单不符" }
	if ($manifest.installerSha256 -ne (Get-FileHash -LiteralPath $installer).Hash) { throw "安装包内容不符" }
	foreach ($file in $files) {
		if (($manifest.files | Where-Object path -EQ $file).sha256 -ne (Get-FileHash -LiteralPath (Join-Path $payload $file)).Hash) { throw "文件内容不符：$file" }
	}
	Write-Host "通过：完整资源、过滤安装器和旧组件、ZIP 往返校验、清单哈希。"
	try {
		& $scriptPath -InstallerPath $installer -OutputDirectory $output
		throw "错误：覆盖现有输出未被拒绝"
	} catch {
		if ($_.Exception.Message -notlike "输出目录已存在*") { throw }
	}
	Set-Content -LiteralPath (Join-Path $payload "dxil.dll") -Value "" -NoNewline
	try {
		& $scriptPath -InstallerPath $installer -OutputDirectory (Join-Path $fixtureRoot "invalid")
		throw "错误：空 DLL 未被拒绝"
	} catch {
		if ($_.Exception.Message -notlike "安装文件为空*") { throw }
	}
	Remove-Item -LiteralPath (Join-Path $payload "dxil.dll")
	try {
		& $scriptPath -InstallerPath $installer -OutputDirectory (Join-Path $fixtureRoot "missing")
		throw "错误：缺失 DLL 未被拒绝"
	} catch {
		if ($_.Exception.Message -notlike "安装包缺少必要组件：dxil.dll*") { throw }
	}
	Write-Host "通过：拒绝覆盖、拒绝空文件、拒绝缺失运行库。"
}
finally {
	if ([IO.Path]::GetFullPath($fixtureRoot).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath())) -and (Split-Path $fixtureRoot -Leaf) -like "lingdong-package-test-*") {
		Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
	}
}
