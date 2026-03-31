param(
  [int]$Port = 5500,
  [string]$Root = "c:\work\workspace"
)

Add-Type -AssemblyName System.Web
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Output "Serving $Root at http://localhost:$Port/"

while ($listener.IsListening) {
  try {
    $context = $listener.GetContext()
    $req = $context.Request
    $res = $context.Response

    $path = [System.Web.HttpUtility]::UrlDecode($req.Url.AbsolutePath.TrimStart('/'))
    if ([string]::IsNullOrWhiteSpace($path)) { $path = 'index.html' }

    $fullPath = Join-Path $Root $path
    if ((Test-Path $fullPath) -and -not (Get-Item $fullPath).PSIsContainer) {
      $bytes = [System.IO.File]::ReadAllBytes($fullPath)
      switch ([System.IO.Path]::GetExtension($fullPath).ToLowerInvariant()) {
        '.html' { $res.ContentType = 'text/html; charset=utf-8' }
        '.js'   { $res.ContentType = 'application/javascript; charset=utf-8' }
        '.css'  { $res.ContentType = 'text/css; charset=utf-8' }
        '.json' { $res.ContentType = 'application/json; charset=utf-8' }
        '.png'  { $res.ContentType = 'image/png' }
        '.jpg'  { $res.ContentType = 'image/jpeg' }
        '.jpeg' { $res.ContentType = 'image/jpeg' }
        '.svg'  { $res.ContentType = 'image/svg+xml' }
        default { $res.ContentType = 'application/octet-stream' }
      }
      $res.StatusCode = 200
      $res.ContentLength64 = $bytes.Length
      $res.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
      $msg = [System.Text.Encoding]::UTF8.GetBytes('404 Not Found')
      $res.StatusCode = 404
      $res.ContentType = 'text/plain; charset=utf-8'
      $res.ContentLength64 = $msg.Length
      $res.OutputStream.Write($msg, 0, $msg.Length)
    }

    $res.OutputStream.Close()
  } catch {
    break
  }
}

$listener.Stop()
