$enc = [Text.UTF8Encoding]::new($true)
function Edit-Source($file, $old, $new) {
 $p = Join-Path $PWD $file; $s = [IO.File]::ReadAllText($p)
 if (-not $s.Contains($old)) { throw "Not found: $file : $old" }
 [IO.File]::WriteAllText($p,$s.Replace($old,$new),$enc)
}
