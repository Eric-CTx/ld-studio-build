param(
	[Parameter(Mandatory)][string]$InstallerPath,
	[Parameter(Mandatory)][string]$OutputDirectory
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$installer = (Resolve-Path -LiteralPath $InstallerPath).Path
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) { throw "输出目录已存在，拒绝覆盖：$output" }
$scratch = Join-Path ([IO.Path]::GetTempPath()) ("lingdong-package-" + [guid]::NewGuid())
$extract = Join-Path $scratch "nsis"
$portable = Join-Path $scratch "灵动录屏_免安装版"
$roundtrip = Join-Path $scratch "zip-check"
$required = @(
	"Cap.exe", "cap-muxer.exe", "cap-cli.exe",
	"avcodec-61.dll", "avdevice-61.dll", "avfilter-10.dll", "avformat-61.dll",
	"avutil-59.dll", "postproc-58.dll", "swresample-5.dll", "swscale-8.dll",
	"dxcompiler.dll", "dxil.dll", "onnxruntime.dll", "onnxruntime_providers_shared.dll"
)

try {
	$null = New-Item -ItemType Directory -Path $extract, $portable -Force
	& 7z x $installer "-o$extract" -y | Out-Host
	if ($LASTEXITCODE -ne 0) { throw "NSIS 载荷提取失败" }
	$entries = @(foreach ($file in Get-ChildItem -LiteralPath $extract -File -Recurse) {
		$relative = [IO.Path]::GetRelativePath($extract, $file.FullName).Replace("\", "/")
		if ($relative -match '^\$PLUGINSDIR/' -or $relative -in @("cap-gpui.exe", "cap-exporter.exe") -or $relative -match '^assets/rive/') { continue }
		if ($relative -notmatch '^(Cap\.exe|cap-muxer\.exe|cap-cli\.exe|[^/]+\.dll|licenses/dxc/[^/]+\.txt|assets/backgrounds/.+|assets/music/[^/]+\.mp3)$') {
			throw "NSIS 出现未核对的安装文件：$relative"
		}
		if ($file.Length -eq 0) { throw "安装文件为空：$relative" }
		$destination = Join-Path $portable $relative
		$null = New-Item -ItemType Directory -Path (Split-Path $destination) -Force
		Copy-Item -LiteralPath $file.FullName -Destination $destination
		[ordered]@{ path = $relative; size = $file.Length; sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash }
	})
	foreach ($name in $required) {
		if ($name -notin $entries.path) { throw "安装包缺少必要组件：$name" }
	}
	foreach ($prefix in @("licenses/dxc/", "assets/music/", "assets/backgrounds/macOS/", "assets/backgrounds/blue/", "assets/backgrounds/cities/", "assets/backgrounds/dark/", "assets/backgrounds/orange/", "assets/backgrounds/purple/")) {
		if (-not @($entries | Where-Object { $_.path.StartsWith($prefix) }).Count) { throw "安装包缺少资源：$prefix" }
	}
	$null = New-Item -ItemType Directory -Path $output
	$zip = Join-Path $output "灵动录屏_免安装版.zip"
	Compress-Archive -LiteralPath $portable -DestinationPath $zip
	Expand-Archive -LiteralPath $zip -DestinationPath $roundtrip
	$restored = Join-Path $roundtrip "灵动录屏_免安装版"
	if (@(Get-ChildItem -LiteralPath $restored -File -Recurse).Count -ne $entries.Count) { throw "ZIP 文件数量不符" }
	foreach ($entry in $entries) {
		if ((Get-FileHash -LiteralPath (Join-Path $restored $entry.path) -Algorithm SHA256).Hash -ne $entry.sha256) { throw "ZIP 文件校验失败：$($entry.path)" }
	}
	$setup = Join-Path $output "灵动录屏_安装版.exe"
	Copy-Item -LiteralPath $installer -Destination $setup
	[ordered]@{
		commit = $env:GITHUB_SHA
		createdUtc = [DateTimeOffset]::UtcNow.ToString("o")
		installerSha256 = (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash
		portableSha256 = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
		files = $entries
	} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output "构建校验.json") -Encoding utf8
	Write-Host "已验证 $($entries.Count) 个安装载荷文件及 ZIP 往返 SHA-256。"
}
finally {
	if ([IO.Path]::GetFullPath($scratch).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath())) -and (Split-Path $scratch -Leaf) -like "lingdong-package-*") {
		Remove-Item -LiteralPath $scratch -Recurse -Force
	}
}
