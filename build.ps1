# 야자 설정집 · 커미션 시트 빌드
#
#   설정집_소스.html  ─┐
#   커미션_소스.html  ─┴─ 이미지 자리표시자 {{IMG:이름}} / {{THUMB:이름}} 를 채워 두 가지로 뽑는다
#
#   [1] 아티팩트용 — 이미지를 base64로 박은 한 파일
#         야자_설정집.html
#         커미션_시트.html
#       Claude 아티팩트는 파일 하나만 받으므로 인라인이어야 한다.
#
#   [2] GitHub Pages용 — 이미지를 images\ 로 분리하고 경로만 걸어둔 가벼운 HTML
#         index.html               ->  /
#         commission\index.html    ->  /commission/
#         images\*.jpg             (yt\web 에서 복사)
#       HTML이 40KB 남짓이라 글자가 먼저 뜨고 그림이 뒤따라 채워진다.
#
# 내용을 고칠 때는 *_소스.html 쪽을 고치고 이 스크립트를 다시 돌릴 것.
# 결과물은 매번 새로 생성되므로 직접 고치면 날아간다.
#
# 이미지를 추가하려면: yt\web\<이름>.jpg 와 yt\web\thumb-<이름>.jpg 를 넣고
# 소스에서 {{IMG:<이름>}} / {{THUMB:<이름>}} 으로 참조하면 된다.
#
# 이 파일은 반드시 BOM 있는 UTF-8로 저장할 것. (PowerShell 5.1이 BOM 없는 UTF-8을
# ANSI로 읽어 한글 경로가 깨진다. Write 도구로 고친 뒤에는 BOM을 다시 붙일 것.)

$ErrorActionPreference = 'Stop'

$root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$imgSrc  = Join-Path $root 'yt\web'
$imgOut  = Join-Path $root 'images'
$utf8    = New-Object System.Text.UTF8Encoding($false)
$rx      = '\{\{(IMG|THUMB):([A-Za-z0-9_-]+)\}\}'

# Source   편집용 소스
# Artifact 아티팩트용 결과물 (루트에 생성)
# Pages    Pages용 하위 폴더. 빈 문자열이면 저장소 루트
# Up       Pages 문서에서 images\ 까지의 상대 경로
$targets = @(
  @{ Source = '설정집_소스.html'; Artifact = '야자_설정집.html'; Pages = '';           Up = '' }
  @{ Source = '커미션_소스.html'; Artifact = '커미션_시트.html'; Pages = 'commission'; Up = '../' }
)

function Resolve-ImagePath {
  param([string]$Kind, [string]$Name)
  $file = if ($Kind -eq 'THUMB') { "thumb-$Name.jpg" } else { "$Name.jpg" }
  $path = Join-Path $imgSrc $file
  if (-not (Test-Path $path)) { throw "이미지를 찾을 수 없음: yt\web\$file" }
  ,@($file, $path)
}

function Expand-Inline {
  param([string]$Text)
  [regex]::Replace($Text, $rx, {
    param($m)
    $r = Resolve-ImagePath $m.Groups[1].Value $m.Groups[2].Value
    "data:image/jpeg;base64," + [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($r[1]))
  })
}

function Expand-Linked {
  param([string]$Text, [string]$Up)
  [regex]::Replace($Text, $rx, {
    param($m)
    $r = Resolve-ImagePath $m.Groups[1].Value $m.Groups[2].Value
    "$Up" + "images/" + $r[0]
  })
}

function Wrap-Document {
  param([string]$Fragment)
  # 조각 파일은 <title>/<link>/<style> 로 시작한다. </style> 를 기준으로 head 와 body 를 나눈다.
  $marker = '</style>'
  $cut = $Fragment.IndexOf($marker)
  if ($cut -lt 0) { throw '소스에서 </style> 를 찾을 수 없음' }
  $head = $Fragment.Substring(0, $cut + $marker.Length)
  $body = $Fragment.Substring($cut + $marker.Length)
  @"
<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<meta name="color-scheme" content="light dark">
$head
</head>
<body>$body
</body>
</html>
"@
}

# --- 이미지를 배포용 폴더로 복사 ---
New-Item -ItemType Directory -Force $imgOut | Out-Null
Get-ChildItem "$imgOut\*.jpg" -ErrorAction SilentlyContinue | Remove-Item -Force
Copy-Item "$imgSrc\*.jpg" $imgOut -Force
$imgCount = (Get-ChildItem "$imgOut\*.jpg").Count
$imgMb = [math]::Round(((Get-ChildItem "$imgOut\*.jpg" | Measure-Object Length -Sum).Sum) / 1MB, 2)
Write-Output "images\  ->  $($imgCount)개, $imgMb MB"
Write-Output ''

foreach ($t in $targets) {
  $srcPath = Join-Path $root $t.Source
  if (-not (Test-Path $srcPath)) { throw "소스가 없음: $($t.Source)" }
  $raw = [System.IO.File]::ReadAllText($srcPath, [System.Text.Encoding]::UTF8)

  # [1] 아티팩트용 — 인라인
  $artifactPath = Join-Path $root $t.Artifact
  [System.IO.File]::WriteAllText($artifactPath, (Expand-Inline $raw), $utf8)

  # [2] Pages용 — 이미지 분리
  $pagesDir = if ($t.Pages) { Join-Path $root $t.Pages } else { $root }
  New-Item -ItemType Directory -Force $pagesDir | Out-Null
  $pagesPath = Join-Path $pagesDir 'index.html'
  [System.IO.File]::WriteAllText($pagesPath, (Wrap-Document (Expand-Linked $raw $t.Up)), $utf8)

  $mbA = [math]::Round((Get-Item $artifactPath).Length / 1MB, 2)
  $kbP = [math]::Round((Get-Item $pagesPath).Length / 1KB)
  Write-Output "$($t.Source)"
  Write-Output "    아티팩트용 : $artifactPath  ($mbA MB / 한도 16MB)"
  Write-Output "    Pages용    : $pagesPath  ($($kbP) KB + images\)"
  if ($mbA -gt 15) { Write-Warning "$($t.Artifact) 가 16MB 한도에 근접했다. 이미지를 더 줄일 것." }
}

Write-Output ''
Write-Output 'GitHub Pages 소스를 저장소 루트로 두면  /  와  /commission/  두 페이지가 된다.'
Write-Output 'images\ 폴더도 반드시 함께 커밋할 것. 빠지면 그림이 전부 깨진다.'
